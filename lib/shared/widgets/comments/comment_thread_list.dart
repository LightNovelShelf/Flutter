import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../features/book/book_providers.dart';
import '../app_dialogs.dart';
import '../skeleton.dart';
import '../state_views.dart';
import 'comment_compose_sheet.dart';
import 'thread_reply_row.dart';

/// 扁平行：主评论后面直接跟它的回复，长列表能按行回收。
sealed class _CommentRow {
  const _CommentRow();
}

class _RootRow extends _CommentRow {
  const _RootRow(this.comment, {required this.closesGroup});

  final CommentItem comment;
  final bool closesGroup;
}

class _ReplyRow extends _CommentRow {
  const _ReplyRow(this.parent, this.reply, {required this.closesGroup});

  final CommentItem parent;
  final CommentReply reply;
  final bool closesGroup;
}

List<_CommentRow> _flatten(List<CommentItem> items) {
  final rows = <_CommentRow>[];
  for (final item in items) {
    rows.add(_RootRow(item, closesGroup: item.replies.isEmpty));
    for (var index = 0; index < item.replies.length; index += 1) {
      rows.add(
        _ReplyRow(
          item,
          item.replies[index],
          closesGroup: index == item.replies.length - 1,
        ),
      );
    }
  }
  return rows;
}

/// 评论列表，自带分页/骨架/空态/错误态。
/// `header` 作为列表首项渲染，与列表共用一个滚动视图。
class CommentThreadList extends ConsumerStatefulWidget {
  const CommentThreadList({
    super.key,
    required this.target,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 48),
  });

  final CommentTarget target;
  final Widget? header;
  final EdgeInsets padding;

  @override
  ConsumerState<CommentThreadList> createState() => _CommentThreadListState();
}

class _CommentThreadListState extends ConsumerState<CommentThreadList> {
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.pixels <
        notification.metrics.maxScrollExtent - 480) {
      return false;
    }
    final state = ref.read(commentThreadProvider(widget.target)).value;
    if (state == null || state.loadingMore || !state.hasMore) return false;
    if (state.moreError != null) return false;
    ref.read(commentThreadProvider(widget.target).notifier).loadMore();
    return false;
  }

  Future<void> _reply(CommentItem parent, CommentReply? reply) async {
    await showCommentComposeSheet(
      context,
      target: widget.target,
      parentId: parent.id,
      replyId: reply?.id,
      replyToUserName: reply?.user.userName ?? parent.user.userName,
    );
  }

  Future<void> _delete(int commentId) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '删除评论',
      message: '此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(commentThreadProvider(widget.target).notifier)
          .delete(commentId);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        describeCommentError(error, fallback: '无法删除评论。'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentThreadProvider(widget.target));
    final state = async.value;

    if (state == null) {
      final body = async.hasError
          ? ErrorStateView(
              message: describeCommentError(async.error!, fallback: '无法加载评论。'),
              onRetry: () =>
                  ref.invalidate(commentThreadProvider(widget.target)),
            )
          : const _CommentThreadSkeleton();
      return ListView(
        padding: widget.padding,
        children: <Widget>[if (widget.header != null) widget.header!, body],
      );
    }

    final rows = _flatten(state.items);
    final headerCount = widget.header == null ? 0 : 1;
    final footerCount = 1;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        padding: widget.padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: headerCount + (rows.isEmpty ? 1 : rows.length) + footerCount,
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) return widget.header!;
          final offset = index - headerCount;
          if (rows.isEmpty) {
            if (offset == 0) {
              return const EmptyStateView(
                icon: Icons.mode_comment_outlined,
                title: '还没有评论。',
              );
            }
            return _footer(state);
          }
          if (offset >= rows.length) return _footer(state);
          final row = rows[offset];
          return switch (row) {
            _RootRow(:final comment, :final closesGroup) => ThreadReplyGroup(
              isChild: false,
              closesGroup: closesGroup,
              child: ThreadReplyRow(
                userName: comment.user.userName,
                avatarUrl: comment.user.avatarUrl,
                content: comment.content,
                publishedAt: comment.createdAt,
                isChild: false,
                actions: _actions(
                  isChild: false,
                  canEdit: comment.canEdit,
                  onReply: () => _reply(comment, null),
                  onDelete: () => _delete(comment.id),
                ),
              ),
            ),
            _ReplyRow(:final parent, :final reply, :final closesGroup) =>
              ThreadReplyGroup(
                isChild: true,
                closesGroup: closesGroup,
                child: ThreadReplyRow(
                  userName: reply.user.userName,
                  avatarUrl: reply.user.avatarUrl,
                  content: reply.content,
                  publishedAt: reply.createdAt,
                  isChild: true,
                  replyToUserName: reply.replyToUser?.userName,
                  actions: _actions(
                    isChild: true,
                    canEdit: reply.canEdit,
                    onReply: () => _reply(parent, reply),
                    onDelete: () => _delete(reply.id),
                  ),
                ),
              ),
          };
        },
      ),
    );
  }

  Widget _footer(CommentThreadState state) => ListFooterStatus(
    loading: state.loadingMore,
    hasMore: state.hasMore,
    endLabel: state.items.isEmpty ? '' : '没有更多评论了',
    error: state.moreError,
    onRetry: () =>
        ref.read(commentThreadProvider(widget.target).notifier).loadMore(),
  );

  /// 评论行的操作：回复，以及自己的评论才有的删除。
  List<Widget> _actions({
    required bool isChild,
    required bool canEdit,
    required VoidCallback onReply,
    required VoidCallback onDelete,
  }) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = threadRowIconSize(isChild);
    return <Widget>[
      ThreadRowIconButton(
        icon: Icons.reply,
        tooltip: '回复',
        iconSize: iconSize,
        color: colors.onSurfaceVariant,
        onPressed: onReply,
      ),
      if (canEdit)
        ThreadRowIconButton(
          icon: Icons.delete_outline,
          tooltip: '删除',
          iconSize: iconSize,
          color: colors.error,
          onPressed: onDelete,
        ),
    ];
  }
}

class _CommentThreadSkeleton extends StatelessWidget {
  const _CommentThreadSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: List<Widget>.generate(
      8,
      (_) => const Padding(
        padding: EdgeInsets.only(bottom: 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SkeletonBox(height: 40, width: 40, radius: 20),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(height: 3),
                  SkeletonBox(height: 13, widthFactor: 1, radius: 6),
                  SizedBox(height: 7),
                  SkeletonBox(height: 13, widthFactor: 1, radius: 6),
                  SizedBox(height: 7),
                  SkeletonBox(height: 13, widthFactor: 0.72, radius: 6),
                  SizedBox(height: 11),
                  SkeletonBox(height: 11, widthFactor: 0.32, radius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
