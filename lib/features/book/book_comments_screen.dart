import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/models.dart';
import 'widgets/comment_thread.dart';

class BookCommentsScreen extends ConsumerStatefulWidget {
  const BookCommentsScreen({
    super.key,
    required this.id,
    required this.title,
    required this.targetType,
    this.seriesTitle,
  });

  final int id;
  final String title;
  final CommentTargetType targetType;
  final String? seriesTitle;

  @override
  ConsumerState<BookCommentsScreen> createState() => _BookCommentsScreenState();
}

class _BookCommentsScreenState extends ConsumerState<BookCommentsScreen> {
  /// 漫画评论挂系列，`id` 恒为 0。
  CommentTarget get _target => widget.targetType == CommentTargetType.series
      ? CommentTarget.series(widget.seriesTitle ?? widget.title)
      : CommentTarget.book(widget.id);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('评论'),
            if (widget.title.isNotEmpty)
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '写评论',
            onPressed: () => showCommentComposeSheet(context, target: _target),
          ),
        ],
      ),
      body: CommentThreadList(target: _target),
    );
  }
}
