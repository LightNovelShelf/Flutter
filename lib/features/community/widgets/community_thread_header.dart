import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/html_content.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../community_thread_providers.dart';
import 'community_primitives.dart';

/// 帖子头部及正文。
class CommunityThreadHeader extends StatelessWidget {
  const CommunityThreadHeader({
    super.key,
    required this.detail,
    required this.controller,
    required this.threadActionBusy,
    required this.canReply,
    required this.error,
    required this.onReply,
  });

  final CommunityThreadDetail detail;
  final CommunityThreadController controller;
  final bool threadActionBusy;
  final bool canReply;
  final String? error;
  final Future<void> Function() onReply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final item = detail.item;
    final subCategory = item.subCategoryLabel?.trim() ?? '';
    final authorName = displayUserName(
      item.authorName,
      deleted: item.authorIsDeleted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CommunityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (item.boardName.trim().isNotEmpty)
                      CommunityTagPill(label: item.boardName),
                    if (subCategory.isNotEmpty)
                      CommunityTagPill(
                        label: subCategory,
                        tone: CommunityTagTone.neutral,
                      ),
                    if (item.locked)
                      const CommunityTagPill(
                        label: '已锁定',
                        tone: CommunityTagTone.locked,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 27,
                        height: 34 / 27,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: <Widget>[
                        UserAvatar(
                          url: item.authorAvatar,
                          name: authorName,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                authorName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatRelativeTimeFine(item.publishedAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    HtmlContent(html: detail.content),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _ActionButton(
                      icon: detail.liked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: formatCompactCount(item.likes),
                      filled: detail.liked,
                      onPressed: item.locked || threadActionBusy
                          ? null
                          : controller.toggleLike,
                    ),
                    _ActionButton(
                      icon: detail.favorited
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      label: formatCompactCount(item.favorites),
                      filled: detail.favorited,
                      onPressed: item.locked || threadActionBusy
                          ? null
                          : controller.toggleFavorite,
                    ),
                    FilledButton.icon(
                      onPressed: canReply ? onReply : null,
                      icon: const Icon(Icons.mode_comment_outlined, size: 18),
                      label: const Text('回复'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (item.locked) ...<Widget>[
          const SizedBox(height: 14),
          CommunityCard(
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '此讨论已锁定，无法再进行互动或回复。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 19 / 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: 14),
          CommunityStateCard(
            title: '社区操作失败',
            description: error!,
            isError: true,
            onRetry: controller.retry,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          '回复 · ${formatCompactCount(detail.repliesPage.total)}',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    if (filled) {
      return FilledButton.tonal(onPressed: onPressed, child: child);
    }
    return TextButton(onPressed: onPressed, child: child);
  }
}
