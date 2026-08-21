import 'package:flutter/material.dart';

import '../../../data/api/community_models.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'community_primitives.dart';

/// 帖子详情里的一条回复（父级/子级共用）。
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
    final colors = Theme.of(context).colorScheme;
    final name = displayUserName(
      reply.authorName,
      deleted: reply.authorIsDeleted,
    );
    final badge = reply.authorBadge?.trim() ?? '';
    final replyToName = reply.replyTo == null
        ? ''
        : displayUserName(
            reply.replyTo!.authorName,
            deleted: reply.replyTo!.authorIsDeleted,
          );

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (isChild)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              UserAvatar(url: reply.authorAvatar, name: name, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (replyToName.isNotEmpty)
                        TextSpan(
                          text: ' 回复了 $replyToName',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (badge.isNotEmpty)
                CommunityTagPill(
                  label: badge,
                  tone: CommunityTagTone.neutral,
                  dense: true,
                ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              UserAvatar(url: reply.authorAvatar, name: name, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 19 / 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (badge.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 8),
                          CommunityTagPill(
                            label: badge,
                            tone: CommunityTagTone.neutral,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    if (replyToName.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '回复 $replyToName',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: isChild ? 0 : 56),
          child: SelectionArea(
            child: Text(
              reply.content.trim(),
              style: TextStyle(
                fontSize: 14,
                height: 19 / 14,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: isChild ? 0 : 56),
          child: _ReplyActions(
            reply: reply,
            compact: isChild,
            canReply: canReply,
            busy: busy,
            onLike: onLike,
            onReply: onReply,
          ),
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: highlighted ? colors.primaryContainer : Colors.transparent,
        border: highlighted
            ? Border(left: BorderSide(color: colors.primary, width: 3))
            : null,
        borderRadius: BorderRadius.circular(highlighted ? 12 : 0),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: highlighted ? 6 : 0,
        vertical: isChild ? 2 : 8,
      ),
      child: content,
    );
  }
}

class _ReplyActions extends StatelessWidget {
  const _ReplyActions({
    required this.reply,
    required this.compact,
    required this.canReply,
    required this.busy,
    required this.onLike,
    required this.onReply,
  });

  final CommunityThreadReply reply;
  final bool compact;
  final bool canReply;
  final bool busy;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = compact ? 16.0 : 18.0;
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatRelativeTimeFine(reply.publishedAt),
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          InkWell(
            onTap: busy ? null : onLike,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    reply.liked ? Icons.favorite : Icons.favorite_border,
                    size: iconSize,
                    color: reply.liked
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCompactCount(reply.likes),
                    style: communityTabular.copyWith(
                      fontSize: 12,
                      color: reply.liked
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: iconSize,
              onPressed: canReply && !busy ? onReply : null,
              icon: const Icon(Icons.reply),
              tooltip: '回复',
            ),
          ),
        ],
      ),
    );
  }
}
