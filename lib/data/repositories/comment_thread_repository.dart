import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/network/api_error.dart';
import '../../shared/paging/paged_list.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';

/// 评论目标。作为 family 键需要值相等。
@immutable
class CommentTarget {
  const CommentTarget({required this.type, required this.id});

  const CommentTarget.book(int bookId)
    : type = CommentTargetType.book,
      id = bookId;

  const CommentTarget.announcement(int announcementId)
    : type = CommentTargetType.announcement,
      id = announcementId;

  final CommentTargetType type;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is CommentTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
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
      .getComments(type: arg.type, id: arg.id, page: page);

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
