import 'package:flutter/material.dart';

import '../../../data/api/community_models.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/comments/thread_reply_row.dart';
import 'community_primitives.dart';

/// 帖子详情里的一条回复（父级/子级共用），版式与评论列表共用 [ThreadReplyRow]。
class CommunityReplyRow extends StatelessWidget {
  const CommunityReplyRow({
    super.key,
    required this.reply,
    required this.isChild,
    required this.highlighted,
    required this.canReply,
    required this.busy,
    required this.onLike,
    required this.onReply,
  });

  final CommunityThreadReply reply;
  final bool isChild;
  final bool highlighted;
  final bool canReply;
  final bool busy;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final name = displayUserName(
      reply.authorName,
      deleted: reply.authorIsDeleted,
    );
    final badge = reply.authorBadge?.trim() ?? '';
    final iconSize = threadRowIconSize(isChild);

    return ThreadReplyRow(
      userName: name,
      avatarUrl: reply.authorAvatar,
      content: reply.content,
      publishedAt: reply.publishedAt,
      isChild: isChild,
      highlighted: highlighted,
      replyToUserName: reply.replyTo == null
          ? null
          : displayUserName(
              reply.replyTo!.authorName,
              deleted: reply.replyTo!.authorIsDeleted,
            ),
      badge: badge.isEmpty
          ? null
          : CommunityTagPill(
              label: badge,
              tone: CommunityTagTone.neutral,
              dense: true,
            ),
      actions: <Widget>[
        _LikeButton(
          liked: reply.liked,
          likes: reply.likes,
          iconSize: iconSize,
          onPressed: busy ? null : onLike,
        ),
        const SizedBox(width: 8),
        ThreadRowIconButton(
          icon: Icons.reply,
          tooltip: '回复',
          iconSize: iconSize,
          onPressed: canReply && !busy ? onReply : null,
        ),
      ],
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.likes,
    required this.iconSize,
    required this.onPressed,
  });

  final bool liked;
  final int likes;
  final double iconSize;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = liked ? colors.primary : colors.onSurfaceVariant;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: iconSize,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              formatCompactCount(likes),
              style: communityTabular.copyWith(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
