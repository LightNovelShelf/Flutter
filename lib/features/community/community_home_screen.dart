import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/community_models.dart';
import '../../data/repositories/profile_repository.dart';
import 'community_providers.dart';
import 'widgets/community_widgets.dart';

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

/// 社区首页：概览、筛选、帖子流、榜单。
class CommunityHomeScreen extends ConsumerStatefulWidget {
  const CommunityHomeScreen({super.key});

  @override
  ConsumerState<CommunityHomeScreen> createState() =>
      _CommunityHomeScreenState();
}

class _CommunityHomeScreenState extends ConsumerState<CommunityHomeScreen> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(communityHomeProvider.notifier).ensureLoaded();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    // 距底部不足 720 逻辑像素就预取下一页。
    if (_controller.position.extentAfter < 720) {
      ref.read(communityHomeProvider.notifier).loadMore();
    }
  }

  Future<void> _openAnnouncement(String link) async {
    final uri = Uri.tryParse(link.trim());
    if (uri != null && uri.scheme == 'https') {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) return;
    }
    if (!mounted) return;
    context.push('/announcements');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityHomeProvider);
    final unread =
        ref.watch(profileProvider).valueOrNull?.unreadNotificationCount ?? 0;
    final home = state.home;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/community/compose'),
        tooltip: '发布社区帖子',
        child: const Icon(Icons.edit_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(communityHomeProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              title: const Text('社区'),
              actions: <Widget>[
                IconButton(
                  onPressed: () => context.push('/community/notifications'),
                  tooltip: '通知',
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.notifications_none),
                  ),
                ),
                IconButton(
                  onPressed: () => context.push('/community/mine'),
                  tooltip: '我的社区',
                  icon: const Icon(Icons.person_outline),
                ),
                IconButton(
                  onPressed: () => context.push('/community/rankings'),
                  tooltip: '排行榜',
                  icon: const Icon(Icons.leaderboard_outlined),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              sliver: SliverToBoxAdapter(
                child: home == null
                    ? (state.loading
                          ? const _HeaderSkeleton()
                          : const SizedBox.shrink())
                    : _Header(
                        state: state,
                        onAnnouncementTap: _openAnnouncement,
                      ),
              ),
            ),
            if (home != null)
              SliverToBoxAdapter(child: _BoardStrip(state: state)),
            if (home != null)
              SliverToBoxAdapter(child: _FilterToolbar(state: state)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              sliver: _FeedSliver(state: state),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
              sliver: SliverToBoxAdapter(child: _Footer(state: state)),
            ),
            if (home != null && home.hotThreads.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: CommunityHotThreadsPanel(
                    items: home.hotThreads,
                    onOpen: (id) => context.push('/community/thread/$id'),
                  ),
                ),
              ),
            if (home != null && home.activeUsers.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: CommunityActiveUsersPanel(users: home.activeUsers),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onAnnouncementTap});

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
                    value: formatCommunityCount(home.todayThreads),
                  ),
                  _StatChip(
                    icon: Icons.people_alt_outlined,
                    label: '在线人数',
                    value: formatCommunityCount(home.onlineUserCount),
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

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

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
                      CommunitySkeletonBox(height: 24, widthFactor: 0.62),
                      SizedBox(height: 8),
                      CommunitySkeletonBox(height: 14, widthFactor: 0.82),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                CommunitySkeletonBox(height: 42, width: 42, radius: 14),
              ],
            ),
            SizedBox(height: 14),
            Row(
              children: <Widget>[
                CommunitySkeletonBox(height: 34, width: 132, radius: 14),
                SizedBox(width: 8),
                CommunitySkeletonBox(height: 34, width: 132, radius: 14),
              ],
            ),
          ],
        ),
      ),
      SizedBox(height: 8),
      CommunitySkeletonBox(height: 70, radius: 18),
      SizedBox(height: 8),
    ],
  );
}

class _BoardStrip extends ConsumerWidget {
  const _BoardStrip({required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = buildCommunityBoardOptions(state.home!);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            const CommunityFilterCaption(
              icon: Icons.grid_view_outlined,
              label: '版面',
            ),
            const SizedBox(width: 6),
            for (final CommunityBoardSummary board in boards) ...<Widget>[
              CommunityFilterChip(
                label: board.title,
                icon: resolveCommunityBoardIcon(board.icon, board.title),
                selected: state.query.boardKey == board.key,
                onTap: () => ref
                    .read(communityHomeProvider.notifier)
                    .selectBoard(board.key),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterToolbar extends ConsumerWidget {
  const _FilterToolbar({required this.state});

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
              child: CommunitySkeletonBox(height: 34, radius: 999),
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
                            '${category.label} · ${formatCommunityCount(category.count)}',
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

class _FeedSliver extends ConsumerWidget {
  const _FeedSliver({required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(communityHomeProvider.notifier);
    final children = <Widget>[];

    if (state.home == null) {
      if (state.loading) {
        children.addAll(_skeletons(3));
      } else {
        children.add(
          CommunityStateCard(
            title: '无法加载社区',
            description: state.error ?? '社区暂时不可用。',
            isError: true,
            onRetry: controller.load,
          ),
        );
      }
    } else {
      if (state.error != null) {
        children.add(
          CommunityStateCard(
            title: '无法更新讨论',
            description: state.error!,
            isError: true,
            onRetry: controller.load,
          ),
        );
      }
      if (state.feed.isNotEmpty) {
        children.addAll(
          state.feed.map(
            (item) => CommunityFeedCard(
              item: item,
              onTap: () => context.push('/community/thread/${item.id}'),
            ),
          ),
        );
      } else if (state.loading) {
        children.addAll(_skeletons(3));
      } else {
        children.add(
          const CommunityStateCard(
            title: '还没有讨论',
            description: '可以尝试其他版面或筛选条件，也可以发起第一个讨论。',
          ),
        );
      }
    }

    return SliverList.separated(
      itemCount: children.length,
      itemBuilder: (_, index) => children[index],
      separatorBuilder: (_, _) => const SizedBox(height: 8),
    );
  }

  static List<Widget> _skeletons(int count) =>
      List<Widget>.generate(count, (_) => const CommunityFeedCardSkeleton());
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    if (state.home == null) return const SizedBox.shrink();
    if (state.loadingMore) {
      return const Column(
        children: <Widget>[
          CommunityFeedCardSkeleton(),
          SizedBox(height: 8),
          CommunityFeedCardSkeleton(),
        ],
      );
    }
    if (state.loadMoreError != null) {
      return CommunityStateCard(
        title: '无法加载更多',
        description: state.loadMoreError!,
        isError: true,
        onRetry: ref.read(communityHomeProvider.notifier).loadMore,
      );
    }
    if (!state.feedPage.hasMore && state.feed.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 17,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 7),
          Text(
            '已经全部看完了',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
