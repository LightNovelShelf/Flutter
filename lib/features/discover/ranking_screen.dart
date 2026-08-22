import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/widgets/paged_grid.dart';
import 'catalog_providers.dart';
import 'home_providers.dart';
import 'widgets/book_grid.dart';

/// 排行榜：周期切换，一次返回完整榜单。
class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  HomeRankType _period = HomeRankType.weekly;

  @override
  void initState() {
    super.initState();
    // 初值取自设置，之后仅作页面局部状态，不写回设置。
    _period = ref.read(appSettingsProvider).homeRankType;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rankingProvider(_period));
    final controller = ref.read(rankingProvider(_period).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: PagedGrid.books(
        header: SegmentedButton<HomeRankType>(
          segments: <ButtonSegment<HomeRankType>>[
            for (final period in HomeRankType.values)
              ButtonSegment<HomeRankType>(
                value: period,
                label: Text(rankPeriodLabels[period]!),
              ),
          ],
          selected: <HomeRankType>{_period},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _period = selection.first),
        ),
        books: state.items,
        loading: state.loading,
        errorMessage: state.error,
        onRetry: controller.retry,
        onRefresh: controller.refresh,
        onOpen: (book) => openBookDetail(context, book),
        showRank: true,
        emptyIcon: Icons.emoji_events_outlined,
        emptyTitle: '暂无排行',
        emptyDescription: '当前周期暂无排行数据。',
      ),
    );
  }
}
