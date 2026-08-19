import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_repository.dart';

/// 漫画与小说走不同接口，类型必须进缓存键。
typedef BookDetailRequest = ({int id, BookType? type});

/// 详情页数据包。漫画额外留一份 `ComicInfo`：版本/上传者入口要系列标题与分卷。
@immutable
class BookDetailBundle {
  const BookDetailBundle({required this.detail, this.comic});

  final BookDetail detail;
  final ComicInfo? comic;

  bool get isComic => detail.type == BookType.comic;
}

/// autoDispose：书籍数量无上限，常驻缓存会一直涨。
final AutoDisposeFutureProviderFamily<BookDetailBundle, BookDetailRequest>
bookDetailProvider = FutureProvider.autoDispose
    .family<BookDetailBundle, BookDetailRequest>((ref, request) async {
      final api = ref.watch(apiClientProvider);
      if (request.type == BookType.comic) {
        final comic = await api.getComicInfo(request.id);
        return BookDetailBundle(detail: comic.toBookDetail(), comic: comic);
      }
      return BookDetailBundle(detail: await api.getBookInfo(request.id));
    });

final AutoDisposeFutureProviderFamily<bool, int> bookInShelfProvider =
    FutureProvider.autoDispose.family<bool, int>((ref, bookId) async {
      final snapshot = await ref.watch(shelfProvider.future);
      if (snapshot == null) return false;
      return snapshot.items.any((item) => item.isBook && item.bookId == bookId);
    });

final AutoDisposeFutureProviderFamily<ComicSeriesDetail, String>
comicSeriesProvider = FutureProvider.autoDispose
    .family<ComicSeriesDetail, String>(
      (ref, seriesTitle) =>
          ref.watch(apiClientProvider).getComicSeriesInfo(seriesTitle),
    );

/// 评论目标。漫画按系列聚合（`id` 恒为 0，靠 `seriesTitle` 定位），要值相等才能当 family 键。
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
String describeCommentError(Object error, {required String fallback}) {
  if (error is ApiError) {
    return switch (error.category) {
      ApiErrorCategory.auth => '请重新登录后使用评论功能。',
      ApiErrorCategory.network => '离线时无法加载评论。',
      _ => error.message,
    };
  }
  return fallback;
}

class CommentThreadController
    extends AutoDisposeFamilyAsyncNotifier<CommentThreadState, CommentTarget> {
  Future<CommentPage> _fetch(int page) => ref
      .read(apiClientProvider)
      .getComments(
        type: arg.type,
        id: arg.id,
        page: page,
        seriesTitle: arg.seriesTitle,
      );

  @override
  Future<CommentThreadState> build(CommentTarget arg) async {
    final page = await _fetch(1);
    return CommentThreadState(
      items: page.items,
      page: page.page,
      totalPages: page.totalPages,
    );
  }

  /// 按 id 去重：相邻页在服务端可能重叠。
  static List<CommentItem> _merge(
    List<CommentItem> current,
    List<CommentItem> next,
  ) {
    final seen = <int>{for (final item in current) item.id};
    return <CommentItem>[
      ...current,
      ...next.where((item) => seen.add(item.id)),
    ];
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncValue<CommentThreadState>.data(
      current.copyWith(loadingMore: true, clearMoreError: true),
    );
    try {
      final next = await _fetch(current.page + 1);
      final latest = state.valueOrNull ?? current;
      state = AsyncValue<CommentThreadState>.data(
        latest.copyWith(
          items: _merge(latest.items, next.items),
          page: next.page,
          totalPages: next.totalPages,
          loadingMore: false,
          clearMoreError: true,
        ),
      );
    } catch (error) {
      final latest = state.valueOrNull ?? current;
      state = AsyncValue<CommentThreadState>.data(
        latest.copyWith(
          loadingMore: false,
          moreError: describeCommentError(error, fallback: '无法加载评论。'),
        ),
      );
    }
  }

  /// 静默时只换第一页、不进 loading，避免骨架屏闪一下。
  Future<void> refresh({bool silent = true}) async {
    if (!silent) state = const AsyncValue<CommentThreadState>.loading();
    try {
      final page = await _fetch(1);
      state = AsyncValue<CommentThreadState>.data(
        CommentThreadState(
          items: page.items,
          page: page.page,
          totalPages: page.totalPages,
        ),
      );
    } catch (error, stackTrace) {
      if (state.hasValue && silent) rethrow;
      state = AsyncValue<CommentThreadState>.error(error, stackTrace);
    }
  }

  Future<void> delete(int commentId) async {
    await ref.read(apiClientProvider).deleteComment(commentId);

    final CommentPage page;
    try {
      page = await _fetch(1);
    } catch (error) {
      throw ApiError(
        describeCommentError(error, fallback: '无法刷新评论列表。'),
        ApiErrorCategory.unknown,
      );
    }

    state = AsyncValue<CommentThreadState>.data(
      CommentThreadState(
        items: page.items,
        page: page.page,
        totalPages: page.totalPages,
      ),
    );
  }
}

final AutoDisposeAsyncNotifierProviderFamily<
  CommentThreadController,
  CommentThreadState,
  CommentTarget
>
commentThreadProvider = AsyncNotifierProvider.autoDispose
    .family<CommentThreadController, CommentThreadState, CommentTarget>(
      CommentThreadController.new,
    );
