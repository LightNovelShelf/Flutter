import 'package:flutter/material.dart';

import '../../shared/book_badges.dart';

/// 徽章释义底部面板，吸附在 50% / 100% 两个高度。
Future<void> showBadgeLegendSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 1,
        snap: true,
        snapSizes: const <double>[0.5, 1],
        builder: (_, controller) => _BadgeLegendList(controller: controller),
      ),
    );

class _BadgeLegendList extends StatelessWidget {
  const _BadgeLegendList({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cards = <Widget>[
      for (final definition in bookBadgeDefinitions)
        _BadgeLegendCard(
          previewWidth: 44,
          preview: CategoryBadge(definition: definition),
          label: definition.label,
          meaning: definition.meaning,
        ),
      const _BadgeLegendCard(
        previewWidth: 68,
        preview: LevelBadge(spec: LevelBadgeSpec(level: 6, interior: false)),
        label: 'Level',
        meaning: '权限内容\n图标会按实际 Level 显示',
      ),
      const _BadgeLegendCard(
        previewWidth: 68,
        preview: LevelBadge(spec: LevelBadgeSpec(level: 6, interior: true)),
        label: 'InteriorLevel',
        meaning: '组内权限内容\n图标会按实际 InteriorLevel 显示',
      ),
    ];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.workspace_premium, size: 22, color: colors.primary),
            const SizedBox(width: 10),
            const Text(
              '徽章释义',
              style: TextStyle(
                fontSize: 17,
                height: 22 / 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '以下展示的是 APP 支持的部分类型徽章',
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < cards.length; index += 1) ...<Widget>[
          if (index > 0) const SizedBox(height: 10),
          cards[index],
        ],
      ],
    );
  }
}

class _BadgeLegendCard extends StatelessWidget {
  const _BadgeLegendCard({
    required this.previewWidth,
    required this.preview,
    required this.label,
    required this.meaning,
  });

  final double previewWidth;
  final Widget preview;
  final String label;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: previewWidth,
            child: Align(alignment: Alignment.centerLeft, child: preview),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 21 / 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meaning,
                  style: TextStyle(
                    fontSize: 15,
                    height: 20 / 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
