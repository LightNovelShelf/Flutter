import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../shared/paging/paged_list.dart';

/// 漫画与小说走不同接口，类型必须进缓存键。
typedef BookDetailRequest = ({int id, BookType? type});

/// 详情页数据包。漫画额外带 `ComicInfo`，版本与上传者入口需要系列标题和分卷。
@immutable
class BookDetailBundle {
  const BookDetailBundle({required this.detail, this.comic});

  final BookDetail detail;
  final ComicInfo? comic;

  bool get isComic => detail.type == BookType.comic;
}

/// autoDispose：书籍数量无上限，常驻缓存会持续增长。
final FutureProviderFamily<BookDetailBundle, BookDetailRequest>
bookDetailProvider = FutureProvider.family<BookDetailBundle, BookDetailRequest>(
  (ref, request) async {
    final api = ref.watch(apiClientProvider);
    if (request.type == BookType.comic) {
      final comic = await api.getComicInfo(request.id);
      return BookDetailBundle(detail: comic.toBookDetail(), comic: comic);
    }
    return BookDetailBundle(detail: await api.getBookInfo(request.id));
  },
  isAutoDispose: true,
);

/// 只读缓存快照判定，不回源查询。
final FutureProviderFamily<bool, int> bookInShelfProvider =
    FutureProvider.family<bool, int>((ref, bookId) async {
      final snapshot = await ref.watch(shelfProvider.future);
      if (snapshot == null) return false;
      return shelfContainsBook(snapshot.items, bookId);
    }, isAutoDispose: true);

final FutureProviderFamily<ComicSeriesDetail, String> comicSeriesProvider =
    FutureProvider.family<ComicSeriesDetail, String>(
      (ref, seriesTitle) =>
          ref.watch(apiClientProvider).getComicSeriesInfo(seriesTitle),
      isAutoDispose: true,
    );

/// 评论目标。漫画按系列聚合，`id` 恒为 0，用 `seriesTitle` 定位；作为 family 键需要值相等。
@immutable
class CommentTarget {
  const CommentTarget({required this.type, required this.id, this.seriesTitle});

  const CommentTarget.book(int bookId)
    : type = CommentTargetType.book,
      id = bookId,
      seriesTitle = null;

  const CommentTarget.series(String title)
    : type = CommentTargetType.series,
      id = 0,
      seriesTitle = title;

  const CommentTarget.announcement(int announcementId)
    : type = CommentTargetType.announcement,
      id = announcementId,
      seriesTitle = null;

  final CommentTargetType type;
  final int id;
  final String? seriesTitle;

  @override
  bool operator ==(Object other) =>
      other is CommentTarget &&
      other.type == type &&
      other.id == id &&
      other.seriesTitle == seriesTitle;

  @override
  int get hashCode => Object.hash(type, id, seriesTitle);
}

@immutable
class CommentThreadState {
  const CommentThreadState({
    required this.items,
    required this.page,
    required this.totalPages,
    this.loadingMore = false,
    this.moreError,
  });

  final List<CommentItem> items;
  final int page;
  final int totalPages;
  final bool loadingMore;
  final String? moreError;

  bool get hasMore => page < totalPages;

  CommentThreadState copyWith({
    List<CommentItem>? items,
    int? page,
    int? totalPages,
    bool? loadingMore,
    String? moreError,
    bool clearMoreError = false,
  }) => CommentThreadState(
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: clearMoreError ? null : (moreError ?? this.moreError),
  );
}

/// 认证/离线单独提示，其余沿用服务端消息。
String describeCommentError(Object error, {required String fallback}) =>
    describeApiError(
      error,
      fallback: fallback,
      auth: '请重新登录后使用评论功能。',
      network: '离线时无法加载评论。',
    );

class CommentThreadController extends AsyncNotifier<CommentThreadState> {
  CommentThreadController(this.arg);

  final CommentTarget arg;

  Future<CommentPage> _fetch(int page) => ref
      .read(apiClientProvider)
      .getComments(
        type: arg.type,
        id: arg.id,
        page: page,
        seriesTitle: arg.seriesTitle,
      );

  @override
  Future<CommentThreadState> build() async {
    final page = await _fetch(1);
    return CommentThreadState(
      items: page.items,
      page: page.page,
      totalPages: page.totalPages,
    );
  }

  /// 重新拉取第一页并整份替换，用于刷新与删除后。
  Future<void> _replaceWithFirstPage() async {
    final page = await _fetch(1);
    state = AsyncValue<CommentThreadState>.data(
      CommentThreadState(
        items: page.items,
        page: page.page,
        totalPages: page.totalPages,
      ),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncValue<CommentThreadState>.data(
      current.copyWith(loadingMore: true, clearMoreError: true),
    );
    try {
      final next = await _fetch(current.page + 1);
      final latest = state.value ?? current;
      state = AsyncValue<CommentThreadState>.data(
        latest.copyWith(
          items: mergeById(latest.items, next.items, (item) => item.id),
          page: next.page,
          totalPages: next.totalPages,
          loadingMore: false,
          clearMoreError: true,
        ),
      );
    } catch (error) {
      final latest = state.value ?? current;
      state = AsyncValue<CommentThreadState>.data(
        latest.copyWith(
          loadingMore: false,
          moreError: describeCommentError(error, fallback: '无法加载评论。'),
        ),
      );
    }
  }

  /// 静默时只替换第一页，不进 loading，避免骨架屏闪烁。
  Future<void> refresh({bool silent = true}) async {
    if (!silent) state = const AsyncValue<CommentThreadState>.loading();
    try {
      await _replaceWithFirstPage();
    } catch (error, stackTrace) {
      if (state.hasValue && silent) rethrow;
      state = AsyncValue<CommentThreadState>.error(error, stackTrace);
    }
  }

  Future<void> delete(int commentId) async {
    await ref.read(apiClientProvider).deleteComment(commentId);
    try {
      await _replaceWithFirstPage();
    } catch (error) {
      throw ApiError(
        describeCommentError(error, fallback: '无法刷新评论列表。'),
        ApiErrorCategory.unknown,
      );
    }
  }
}

final AsyncNotifierProviderFamily<
  CommentThreadController,
  CommentThreadState,
  CommentTarget
>
commentThreadProvider =
    AsyncNotifierProvider.family<
      CommentThreadController,
      CommentThreadState,
      CommentTarget
    >(CommentThreadController.new, isAutoDispose: true);

/// 书架按钮的乐观状态：`inShelf` 为 null 表示没有本地覆盖，沿用 [bookInShelfProvider]。
@immutable
class ShelfToggle {
  const ShelfToggle({this.busy = false, this.inShelf, this.error});

  final bool busy;
  final bool? inShelf;
  final String? error;
}

/// 先翻转本地状态再发请求，失败回退到服务端状态并给出提示。
class ShelfToggleController extends Notifier<ShelfToggle> {
  ShelfToggleController(this.arg);

  final int arg;

  @override
  ShelfToggle build() => const ShelfToggle();

  Future<void> toggle(bool inShelf) async {
    state = ShelfToggle(busy: true, inShelf: !inShelf);
    try {
      final result = await ref.read(shelfProvider.notifier).toggleBook(arg);
      if (!ref.mounted) return;
      state = ShelfToggle(inShelf: result);
    } catch (error) {
      if (!ref.mounted) return;
      state = ShelfToggle(
        error: describeApiError(
          error,
          fallback: '无法更新书架。',
          auth: '请重新登录后使用书架。',
          network: '离线时无法修改书架。',
        ),
      );
    }
  }
}

/// autoDispose：乐观状态仅在详情页存续期间有效。
final NotifierProviderFamily<ShelfToggleController, ShelfToggle, int>
shelfToggleProvider =
    NotifierProvider.family<ShelfToggleController, ShelfToggle, int>(
      ShelfToggleController.new,
      isAutoDispose: true,
    );
