import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/comment_thread_repository.dart';
import '../../shared/widgets/comments/comment_compose_sheet.dart';
import '../../shared/widgets/comments/comment_thread_list.dart';

class CommentsScreen extends ConsumerWidget {
  const CommentsScreen({super.key, required this.target, required this.title});

  final CommentTarget target;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('评论'),
            if (title.isNotEmpty)
              Text(
                title,
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
            onPressed: () => showCommentComposeSheet(context, target: target),
          ),
        ],
      ),
      body: CommentThreadList(target: target),
    );
  }
}
