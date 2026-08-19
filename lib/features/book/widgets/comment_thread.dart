import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../data/providers.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/state_views.dart';
import '../book_providers.dart';

// 调用方只 import 这一个文件：评论目标与列表状态一并再导出。
export '../book_providers.dart'
    show
        CommentTarget,
        CommentThreadState,
        commentThreadProvider,
        describeCommentError;

/// 扁平行：主评论后面直接跟它的回复，长列表能按行回收。
sealed class _CommentRow {
  const _CommentRow();
}

class _RootRow extends _CommentRow {
  const _RootRow(this.comment);

  final CommentItem comment;
}

class _ReplyRow extends _CommentRow {
  const _ReplyRow(this.parent, this.reply, {required this.isLast});

  final CommentItem parent;
  final CommentReply reply;
  final bool isLast;
}

List<_CommentRow> _flatten(List<CommentItem> items) {
  final rows = <_CommentRow>[];
  for (final item in items) {
    rows.add(_RootRow(item));
    for (var index = 0; index < item.replies.length; index += 1) {
      rows.add(
        _ReplyRow(
          item,
          item.replies[index],
          isLast: index == item.replies.length - 1,
        ),
      );
    }
  }
  return rows;
}

/// 评论列表，自带分页/骨架/空态/错误态。
/// `header` 作为列表首项渲染（公告详情把正文塞这儿，整页共用一个滚动视图）。
class CommentThreadList extends ConsumerStatefulWidget {
  const CommentThreadList({
    super.key,
    required this.target,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(0, 8, 0, 48),
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
    final state = ref.read(commentThreadProvider(widget.target)).valueOrNull;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(commentThreadProvider(widget.target).notifier)
          .delete(commentId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeCommentError(error, fallback: '无法删除评论。')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentThreadProvider(widget.target));
    final state = async.valueOrNull;

    if (state == null) {
      final body = async.hasError
          ? ErrorStateView(
              message: describeCommentError(
                async.error!,
                fallback: '无法加载评论。',
              ),
              onRetry: () =>
                  ref.invalidate(commentThreadProvider(widget.target)),
            )
          : const _CommentThreadSkeleton();
      return ListView(
        padding: widget.padding,
        children: <Widget>[
          if (widget.header != null) widget.header!,
          body,
        ],
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
            _RootRow(:final comment) => CommentThreadRow(
                userName: comment.user.userName,
                avatarUrl: comment.user.avatarUrl,
                content: comment.content,
                createdAt: comment.createdAt,
                canEdit: comment.canEdit,
                isReply: false,
                isLastReply: false,
                onReply: () => _reply(comment, null),
                onDelete: () => _delete(comment.id),
              ),
            _ReplyRow(:final parent, :final reply, :final isLast) =>
              CommentThreadRow(
                userName: reply.user.userName,
                avatarUrl: reply.user.avatarUrl,
                content: reply.content,
                createdAt: reply.createdAt,
                canEdit: reply.canEdit,
                isReply: true,
                isLastReply: isLast,
                replyToUserName: reply.replyToUser?.userName,
                onReply: () => _reply(parent, reply),
                onDelete: () => _delete(reply.id),
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
}

/// 回复用左侧竖线 + 缩进表达层级，不做无限嵌套。
class CommentThreadRow extends StatelessWidget {
  const CommentThreadRow({
    super.key,
    required this.userName,
    required this.avatarUrl,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    required this.isReply,
    required this.isLastReply,
    this.replyToUserName,
    this.onReply,
    this.onDelete,
  });

  final String userName;
  final String avatarUrl;
  final String content;
  final DateTime createdAt;
  final bool canEdit;
  final bool isReply;
  final bool isLastReply;
  final String? replyToUserName;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final avatarSize = isReply ? 24.0 : 40.0;

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CommentAvatar(url: avatarUrl, name: userName, size: avatarSize),
        SizedBox(width: isReply ? 8 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: userName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (replyToUserName != null)
                      TextSpan(
                        text: ' 回复了 $replyToUserName',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
                style: TextStyle(
                  fontSize: isReply ? 12 : 14,
                  height: isReply ? 1.34 : 1.36,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                content,
                style: text.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.36,
                  color: colors.onSurface,
                ),
              ),
              SizedBox(
                height: 32,
                child: Row(
                  children: <Widget>[
                    Text(
                      formatRelativeTime(createdAt),
                      style: TextStyle(
                        fontSize: isReply ? 10 : 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (onReply != null)
                      _CommentAction(
                        icon: Icons.reply_outlined,
                        tooltip: '回复',
                        size: isReply ? 16 : 18,
                        color: colors.onSurfaceVariant,
                        onPressed: onReply,
                      ),
                    if (canEdit && onDelete != null)
                      _CommentAction(
                        icon: Icons.delete_outline,
                        tooltip: '删除',
                        size: isReply ? 16 : 18,
                        color: colors.error,
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!isReply) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: body,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(72, 2, 16, isLastReply ? 8 : 6),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            ),
          ),
        ),
        child: body,
      ),
    );
  }
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: size, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        splashRadius: 18,
      );
}

/// 无图或加载失败回落到用户名首字。
class CommentAvatar extends StatelessWidget {
  const CommentAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
  });

  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: colors.surfaceContainerHighest,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
          fontSize: size * 0.4 < 11 ? 11 : size * 0.4,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _CommentThreadSkeleton extends StatelessWidget {
  const _CommentThreadSkeleton();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget line(double widthFactor, double height) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: block,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );

    return Column(
      children: List<Widget>.generate(
        8,
        (index) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: block, shape: BoxShape.circle),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 3),
                    line(1, 13),
                    const SizedBox(height: 7),
                    line(1, 13),
                    const SizedBox(height: 7),
                    line(0.72, 13),
                    const SizedBox(height: 11),
                    line(0.32, 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部发表弹窗；成功后刷新对应列表并返回 true。
Future<bool> showCommentComposeSheet(
  BuildContext context, {
  required CommentTarget target,
  int? parentId,
  int? replyId,
  String? replyToUserName,
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    builder: (_) => _CommentComposeSheet(
      target: target,
      parentId: parentId,
      replyId: replyId,
      replyToUserName: replyToUserName,
    ),
  );
  return posted ?? false;
}

class _CommentComposeSheet extends ConsumerStatefulWidget {
  const _CommentComposeSheet({
    required this.target,
    this.parentId,
    this.replyId,
    this.replyToUserName,
  });

  final CommentTarget target;
  final int? parentId;
  final int? replyId;
  final String? replyToUserName;

  @override
  ConsumerState<_CommentComposeSheet> createState() =>
      _CommentComposeSheetState();
}

class _CommentComposeSheetState extends ConsumerState<_CommentComposeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final target = widget.target;
    try {
      if (widget.parentId != null) {
        await api.replyComment(
          type: target.type,
          id: target.id,
          content: content,
          seriesTitle: target.seriesTitle,
          parentId: widget.parentId,
          replyId: widget.replyId,
        );
      } else {
        await api.postComment(
          type: target.type,
          id: target.id,
          content: content,
          seriesTitle: target.seriesTitle,
        );
      }
      await ref.read(commentThreadProvider(target).notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = describeCommentError(error, fallback: '无法发表评论。');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSubmit = _controller.text.trim().isNotEmpty && !_submitting;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104, maxHeight: 148),
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 4000,
                maxLines: null,
                expands: false,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: colors.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: widget.replyToUserName == null
                      ? '写评论'
                      : '回复 ${widget.replyToUserName}',
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  counterText: '',
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(fontSize: 13, height: 1.38, color: colors.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(_submitting ? '正在发布…' : '发布'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
