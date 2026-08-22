import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/skeleton.dart';
import '../community_providers.dart';
import 'community_primitives.dart';

const List<(CommunityFeedOrder, String)> _orderOptions =
    <(CommunityFeedOrder, String)>[
      (CommunityFeedOrder.reply, '最近回复'),
      (CommunityFeedOrder.latest, '最新发布'),
      (CommunityFeedOrder.hot, '热门'),
      (CommunityFeedOrder.featured, '精选'),
    ];

const List<(CommunityFeedScope, String)> _scopeOptions =
    <(CommunityFeedScope, String)>[
      (CommunityFeedScope.all, '全部'),
      (CommunityFeedScope.today, '今天'),
      (CommunityFeedScope.week, '本周'),
    ];

class CommunityBoardStrip extends ConsumerWidget {
  const CommunityBoardStrip({super.key, required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = buildCommunityBoardOptions(state.home!);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        // 横向 ListView 的高度必须由外部给定，34 与胶囊自身的 minHeight 一致。
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: boards.length + 1,
          itemBuilder: (_, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.only(right: 6),
                child: CommunityFilterCaption(
                  icon: Icons.grid_view_outlined,
                  label: '版面',
                ),
              );
            }
            final CommunityBoardSummary board = boards[index - 1];
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: CommunityFilterChip(
                label: board.title,
                icon: resolveCommunityBoardIcon(board.icon, board.title),
                selected: state.query.boardKey == board.key,
                onTap: () => ref
                    .read(communityHomeProvider.notifier)
                    .selectBoard(board.key),
              ),
            );
          },
        ),
      ),
    );
  }
}

class CommunityFilterToolbar extends ConsumerWidget {
  const CommunityFilterToolbar({super.key, required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(communityHomeProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                const CommunityFilterCaption(icon: Icons.sort, label: '排序'),
                const SizedBox(width: 6),
                for (final (CommunityFeedOrder order, String label)
                    in _orderOptions) ...<Widget>[
                  CommunityFilterChip(
                    label: label,
                    selected: state.query.order == order,
                    onTap: () => controller.selectOrder(order),
                  ),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: 6),
                const CommunityFilterCaption(
                  icon: Icons.calendar_today_outlined,
                  label: '时间',
                ),
                const SizedBox(width: 6),
                for (final (CommunityFeedScope scope, String label)
                    in _scopeOptions) ...<Widget>[
                  CommunityFilterChip(
                    label: label,
                    selected: state.query.scope == scope,
                    onTap: () => controller.selectScope(scope),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          if (state.categoriesLoading)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: SkeletonBox(height: 34, radius: 999),
            )
          else if (state.subCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    const CommunityFilterCaption(
                      icon: Icons.category_outlined,
                      label: '分类',
                    ),
                    const SizedBox(width: 6),
                    CommunityFilterChip(
                      label: '全部分类',
                      selected: state.query.subCategoryKey.isEmpty,
                      onTap: () => controller.selectSubCategory(''),
                    ),
                    const SizedBox(width: 6),
                    for (final CommunitySubCategorySummary category
                        in state.subCategories) ...<Widget>[
                      CommunityFilterChip(
                        label:
                            '${category.label} · ${formatCompactCount(category.count)}',
                        selected: state.query.subCategoryKey == category.key,
                        onTap: () => controller.selectSubCategory(category.key),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
