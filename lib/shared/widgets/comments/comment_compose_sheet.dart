import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/comment_thread_repository.dart';
import 'reply_compose_sheet.dart';

/// 底部发表弹窗，成功后刷新对应列表并返回 true。
Future<bool> showCommentComposeSheet(
  BuildContext context, {
  required CommentTarget target,
  int? parentId,
  int? replyId,
  String? replyToUserName,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showReplyComposeSheet(
    context,
    hintText: replyToUserName == null ? '写评论' : '回复 $replyToUserName',
    describeError: (error) => describeCommentError(error, fallback: '无法发表评论。'),
    onSubmit: (content) async {
      final api = container.read(apiClientProvider);
      if (parentId != null) {
        await api.replyComment(
          type: target.type,
          id: target.id,
          content: content,
          parentId: parentId,
          replyId: replyId,
        );
      } else {
        await api.postComment(
          type: target.type,
          id: target.id,
          content: content,
        );
      }
      await container.read(commentThreadProvider(target).notifier).refresh();
    },
  );
}
