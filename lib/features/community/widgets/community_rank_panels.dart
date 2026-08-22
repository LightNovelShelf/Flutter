import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'community_primitives.dart';

/// 前三名的固定配色，第四名起使用中性色。
const List<Color> _rankColors = <Color>[
  Color(0xFFF59E0B),
  Color(0xFFFB7185),
  Color(0xFF60A5FA),
];

class CommunityHotThreadsPanel extends StatelessWidget {
  const CommunityHotThreadsPanel({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<CommunityHotRankItem> items;
  final void Function(int threadId) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CommunityCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.local_fire_department,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '热门讨论',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (int index = 0; index < items.length; index += 1) ...<Widget>[
            if (index > 0) Divider(height: 1, color: colors.outlineVariant),
            InkWell(
              onTap: () => onOpen(items[index].id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    _RankBadge(rank: index + 1),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            items[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(items[index]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 16 / 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(CommunityHotRankItem item) {
    final parts = <String>[
      if (item.boardName.trim().isNotEmpty) item.boardName.trim(),
      '热度 ${formatCompactCount(item.heat)}',
      if (formatRelativeTimeFine(item.publishedAt).isNotEmpty)
        formatRelativeTimeFine(item.publishedAt),
    ];
    return parts.join(' · ');
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = rank <= _rankColors.length ? _rankColors[rank - 1] : null;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent == null
            ? colors.surfaceContainerHighest
            : accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: accent ?? colors.primary,
        ),
      ),
    );
  }
}

class CommunityActiveUsersPanel extends StatelessWidget {
  const CommunityActiveUsersPanel({super.key, required this.users});

  final List<CommunityActiveUserItem> users;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CommunityCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.emoji_events_outlined,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '活跃成员',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (int index = 0; index < users.length; index += 1) ...<Widget>[
            if (index > 0) Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  UserAvatar(
                    url: users[index].avatar,
                    name: users[index].name,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          users[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(users[index]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      formatCompactCount(users[index].score),
                      style: communityTabular.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(CommunityActiveUserItem user) {
    if (user.summary.trim().isNotEmpty) return user.summary.trim();
    if (user.badge.trim().isNotEmpty) return user.badge.trim();
    return '社区成员';
  }
}
