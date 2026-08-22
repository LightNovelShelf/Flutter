import 'package:flutter/foundation.dart';

import '../../data/api/models.dart';
import 'community_reply_tree.dart' as reply_tree;
import 'community_thread_rows.dart';

@immutable
class CommunityThreadState {
  CommunityThreadState({
    this.thread,
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.threadActionBusy = false,
    this.replyActionId,
    this.notice,
    this.noticeTag = 0,
    List<CommunityThreadRow>? rows,
  }) : rows = rows ?? flattenReplyRows(thread);

  final CommunityThreadDetail? thread;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;

  /// 帖子级动作（点赞/收藏）的忙碌位，与回复级动作分开，避免互相禁用。
  final bool threadActionBusy;

  /// 进行中的回复级动作，形如 `like:12` / `children:12`，id 用于定位进度指示。
  final String? replyActionId;

  /// 操作失败的一次性提示，`noticeTag` 每次递增，用于区分文案相同的重复失败。
  final String? notice;
  final int noticeTag;

  /// 回复树摊平成的行，只在 [thread] 换掉时重算。
  /// 列表 delegate 拿这个列表的身份判断能不能跳过重建。
  final List<CommunityThreadRow> rows;

  bool get canReply => thread != null && !thread!.item.locked;

  /// 在回复树中按 id 查找回复。
  CommunityThreadReply? findReply(int id) {
    final detail = thread;
    return detail == null ? null : reply_tree.findReply(detail.replyItems, id);
  }

  static const Object _keep = Object();

  CommunityThreadState copyWith({
    Object? thread = _keep,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _keep,
    Object? loadMoreError = _keep,
    bool? threadActionBusy,
    Object? replyActionId = _keep,
    String? notice,
    int? noticeTag,
  }) {
    final CommunityThreadDetail? nextThread = identical(thread, _keep)
        ? this.thread
        : thread as CommunityThreadDetail?;
    return CommunityThreadState(
      thread: nextThread,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      loadingMore: loadingMore ?? this.loadingMore,
      error: identical(error, _keep) ? this.error : error as String?,
      loadMoreError: identical(loadMoreError, _keep)
          ? this.loadMoreError
          : loadMoreError as String?,
      threadActionBusy: threadActionBusy ?? this.threadActionBusy,
      replyActionId: identical(replyActionId, _keep)
          ? this.replyActionId
          : replyActionId as String?,
      notice: notice ?? this.notice,
      noticeTag: noticeTag ?? this.noticeTag,
      // 帖子数据没换就把摊平结果原样带过去，否则每次状态跳变都要重建全部可见行。
      rows: identical(nextThread, this.thread) ? rows : null,
    );
  }
}
