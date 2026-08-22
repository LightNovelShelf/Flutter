import 'package:flutter/material.dart';

import '../../../shared/format.dart';
import '../../../shared/widgets/skeleton.dart';
import '../community_providers.dart';
import 'community_primitives.dart';

class CommunityHomeHeader extends StatelessWidget {
  const CommunityHomeHeader({
    super.key,
    required this.state,
    required this.onAnnouncementTap,
  });

  final CommunityHomeState state;
  final Future<void> Function(String link) onAnnouncementTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final home = state.home!;
    final board = state.selectedBoard;
    final title = board?.title.trim().isNotEmpty ?? false
        ? board!.title
        : (home.title.trim().isNotEmpty ? home.title : '社区');
    final subtitle = board?.description.trim().isNotEmpty ?? false
        ? board!.description
        : home.subtitle;
    final heat = board == null
        ? ''
        : board.heatLabel.replaceFirst(RegExp(r'^热度'), '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CommunityCard(
          radius: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 22,
                            height: 27 / 22,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        if (subtitle.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            subtitle.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 19 / 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      board == null
                          ? Icons.forum_outlined
                          : resolveCommunityBoardIcon(board.icon, board.title),
                      size: 18,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _StatChip(
                    icon: Icons.grid_view_outlined,
                    label: '今日发帖',
                    value: formatCompactCount(home.todayThreads),
                  ),
                  _StatChip(
                    icon: Icons.people_alt_outlined,
                    label: '在线人数',
                    value: formatCompactCount(home.onlineUserCount),
                  ),
                  if (heat.isNotEmpty)
                    _StatChip(
                      icon: Icons.local_fire_department_outlined,
                      label: '热度',
                      value: heat,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (home.announcement.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          CommunityCard(
            radius: 18,
            padding: const EdgeInsets.all(14),
            onTap: () => onAnnouncementTap(home.announcementLink),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.campaign_outlined,
                    size: 18,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '公告',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        home.announcement.trim(),
                        style: TextStyle(
                          fontSize: 13,
                          height: 19 / 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '查看更多',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 17, color: colors.primary),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityHomeHeaderSkeleton extends StatelessWidget {
  const CommunityHomeHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: const <Widget>[
      CommunityCard(
        radius: 24,
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SkeletonBox(height: 24, widthFactor: 0.62),
                      SizedBox(height: 8),
                      SkeletonBox(height: 14, widthFactor: 0.82),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBox(height: 42, width: 42, radius: 14),
              ],
            ),
            SizedBox(height: 14),
            Row(
              children: <Widget>[
                SkeletonBox(height: 34, width: 132, radius: 14),
                SizedBox(width: 8),
                SkeletonBox(height: 34, width: 132, radius: 14),
              ],
            ),
          ],
        ),
      ),
      SizedBox(height: 8),
      SkeletonBox(height: 70, radius: 18),
      SizedBox(height: 8),
    ],
  );
}
