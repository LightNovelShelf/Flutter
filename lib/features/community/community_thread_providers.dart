import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/paging/paged_list.dart';
import 'community_providers.dart';
import 'community_reply_tree.dart';
import 'community_thread_state.dart';

const int communityReplyPageSize = 5;
const int communityChildReplyPageSize = 3;

/// 帖子详情的分页与乐观互动状态，滚动、高亮等 UI 状态留在页面。
class CommunityThreadController extends Notifier<CommunityThreadState> {
  CommunityThreadController(this.threadId);

  final int threadId;

  /// 世代号，用于丢弃过期请求的响应。
  int _operation = 0;
  bool _disposed = false;

  /// 浏览量只在首次加载时上报，刷新不重复计数。
  bool _viewTracked = false;

  late Future<void> _initialLoad;

  /// 首屏加载的 Future，深链定位需要等它完成。
  Future<void> get initialLoad => _initialLoad;

  @override
  CommunityThreadState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // build 里不能同步改 state，首屏加载推到微任务。
    _initialLoad = Future<void>.microtask(_load);
    return CommunityThreadState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> refresh() => _load(refresh: true);

  Future<void> retry() => _load();

  Future<void> _load({bool refresh = false}) async {
    // 首屏加载在微任务里执行，此时页面可能已销毁。
    if (_disposed) return;
    final token = ++_operation;
    state = state.copyWith(
      loading: !refresh,
      refreshing: refresh,
      error: null,
      loadMoreError: null,
    );
    try {
      final detail = await _api.getCommunityThread(
        threadId: threadId,
        replyPage: 1,
        replySize: communityReplyPageSize,
        trackView: !_viewTracked,
      );
      if (_isStale(token)) return;
      _viewTracked = true;
      state = state.copyWith(thread: detail, loading: false, refreshing: false);
    } catch (error) {
      if (isCancellation(error) || _isStale(token)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: describeCommunityError(error, fallback: '无法加载讨论。'),
      );
    }
  }

  Future<void> loadMore() async {
    final snapshot = state;
    final detail = snapshot.thread;
    if (detail == null ||
        snapshot.loading ||
        snapshot.refreshing ||
        snapshot.loadingMore ||
        !detail.repliesPage.hasMore) {
      return;
    }
    final token = _operation;
    state = state.copyWith(loadingMore: true, loadMoreError: null);
    try {
      final size = detail.repliesPage.size < 1
          ? communityReplyPageSize
          : detail.repliesPage.size;
      final next = await _api.getCommunityThread(
        threadId: threadId,
        replyPage: detail.repliesPage.page + 1,
        replySize: size,
        trackView: false,
      );
      if (_isStale(token)) return;
      final current = state.thread;
      if (next == null || current == null) {
        state = state.copyWith(loadingMore: false);
        return;
      }
      state = state.copyWith(
        loadingMore: false,
        thread: current.copyWith(
          repliesPage: next.repliesPage,
          replyItems: mergeById(
            current.replyItems,
            next.replyItems,
            communityReplyId,
          ),
        ),
      );
    } catch (error) {
      if (isCancellation(error) || _isStale(token)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeCommunityError(error, fallback: '无法加载更多回复。'),
      );
    }
  }

  Future<void> loadChildren(CommunityThreadReply parent) async {
    if (state.replyActionId != null) return;
    state = state.copyWith(replyActionId: 'children:${parent.id}');
    try {
      final size = parent.childPage.size < 1
          ? communityChildReplyPageSize
          : parent.childPage.size;
      final page = parent.childReplies.isEmpty ? 1 : parent.childPage.page + 1;
      final payload = await _api.getCommunityReplyChildren(
        threadId: threadId,
        parentReplyId: parent.id,
        page: page,
        size: size,
      );
      if (_disposed) return;
      final detail = state.thread;
      state = state.copyWith(
        replyActionId: null,
        thread: detail?.copyWith(
          replyItems: updateReplies(
            detail.replyItems,
            parent.id,
            (reply) => reply.copyWith(
              childReplies: mergeById(
                reply.childReplies,
                payload.items,
                communityReplyId,
              ),
              childPage: payload.page,
            ),
          ),
        ),
      );
    } catch (error) {
      if (_disposed) return;
      state = _withNotice(
        state.copyWith(replyActionId: null),
        describeCommunityError(error, fallback: '无法加载更多回复。'),
      );
    }
  }

  Future<void> toggleLike() {
    final detail = state.thread;
    if (detail == null || detail.item.locked) return Future<void>.value();
    return _optimistic<CommunityLikeToggleResult>(
      apply: (current) => _withCounts(
        current.copyWith(liked: !current.liked),
        likes: current.item.likes + (current.liked ? -1 : 1),
      ),
      commit: () => _api.toggleCommunityThreadLike(detail.item.id),
      settle: (current, result) => _withCounts(
        current.copyWith(liked: result.liked),
        likes: result.likes,
      ),
      failure: '无法更新点赞状态。',
    );
  }

  Future<void> toggleFavorite() {
    final detail = state.thread;
    if (detail == null || detail.item.locked) return Future<void>.value();
    return _optimistic<CommunityFavoriteToggleResult>(
      apply: (current) => _withCounts(
        current.copyWith(favorited: !current.favorited),
        favorites: current.item.favorites + (current.favorited ? -1 : 1),
      ),
      commit: () => _api.toggleCommunityThreadFavorite(detail.item.id),
      settle: (current, result) => _withCounts(
        current.copyWith(favorited: result.favorited),
        favorites: result.favorites,
      ),
      failure: '无法更新收藏状态。',
    );
  }

  Future<void> toggleReplyLike(CommunityThreadReply reply) {
    if (!state.canReply) return Future<void>.value();
    return _optimistic<CommunityLikeToggleResult>(
      busyKey: 'like:${reply.id}',
      apply: (current) => current.copyWith(
        replyItems: updateReplies(
          current.replyItems,
          reply.id,
          (item) => item.copyWith(
            liked: !item.liked,
            likes: item.likes + (item.liked ? -1 : 1),
          ),
        ),
      ),
      commit: () => _api.toggleCommunityReplyLike(reply.id),
      settle: (current, result) => current.copyWith(
        replyItems: updateReplies(
          current.replyItems,
          reply.id,
          (item) => item.copyWith(liked: result.liked, likes: result.likes),
        ),
      ),
      // 只回滚这一条，保留期间展开的子回复。
      revert: (current) => current.copyWith(
        replyItems: updateReplies(
          current.replyItems,
          reply.id,
          (item) => item.copyWith(liked: reply.liked, likes: reply.likes),
        ),
      ),
      failure: '无法更新点赞状态。',
    );
  }

  /// 发布回复，不更新本地状态。
  Future<void> postReply({required String content, int? replyToId}) async {
    await _api.createCommunityReply(
      threadId: threadId,
      content: content,
      replyToId: replyToId,
    );
  }

  /// 乐观更新：先本地翻转，服务端返回后用真实计数覆盖，失败回滚并提示。
  /// `busyKey` 为空表示帖子级动作，否则占用回复级忙碌位。
  Future<void> _optimistic<R>({
    required CommunityThreadDetail Function(CommunityThreadDetail detail) apply,
    required Future<R> Function() commit,
    required CommunityThreadDetail Function(
      CommunityThreadDetail detail,
      R result,
    )
    settle,
    required String failure,
    CommunityThreadDetail Function(CommunityThreadDetail detail)? revert,
    String? busyKey,
  }) async {
    final snapshot = state.thread;
    if (snapshot == null) return;
    if (busyKey == null
        ? state.threadActionBusy
        : state.replyActionId != null) {
      return;
    }
    state = _hold(state.copyWith(thread: apply(snapshot)), busyKey);
    try {
      final result = await commit();
      if (_disposed) return;
      final current = state.thread;
      state = _release(
        state.copyWith(
          thread: current == null ? null : settle(current, result),
        ),
        busyKey,
      );
    } catch (error) {
      if (_disposed) return;
      final current = state.thread;
      // 未提供 revert 时整份回到发起前的快照。
      final CommunityThreadDetail? rolledBack = revert == null
          ? snapshot
          : (current == null ? null : revert(current));
      state = _withNotice(
        _release(state.copyWith(thread: rolledBack), busyKey),
        describeCommunityError(error, fallback: failure),
      );
    }
  }

  CommunityThreadState _hold(CommunityThreadState next, String? busyKey) =>
      busyKey == null
      ? next.copyWith(threadActionBusy: true)
      : next.copyWith(replyActionId: busyKey);

  CommunityThreadState _release(CommunityThreadState next, String? busyKey) =>
      busyKey == null
      ? next.copyWith(threadActionBusy: false)
      : next.copyWith(replyActionId: null);

  CommunityThreadState _withNotice(CommunityThreadState next, String message) =>
      next.copyWith(notice: message, noticeTag: next.noticeTag + 1);

  bool _isStale(int token) => _disposed || token != _operation;
}

final NotifierProviderFamily<
  CommunityThreadController,
  CommunityThreadState,
  int
>
communityThreadProvider =
    NotifierProvider.family<
      CommunityThreadController,
      CommunityThreadState,
      int
    >(CommunityThreadController.new, isAutoDispose: true);

/// 复制帖子并替换互动计数。
CommunityThreadDetail _withCounts(
  CommunityThreadDetail detail, {
  int? likes,
  int? favorites,
}) => CommunityThreadDetail(
  item: detail.item.copyWith(likes: likes, favorites: favorites),
  liked: detail.liked,
  favorited: detail.favorited,
  bodyHtml: detail.bodyHtml,
  repliesPage: detail.repliesPage,
  replyItems: detail.replyItems,
  relatedThreads: detail.relatedThreads,
);
