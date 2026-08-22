import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/profile_repository.dart';
import '../../shared/paging/scroll_prefetch.dart';
import 'community_providers.dart';
import 'widgets/community_feed_card.dart';
import 'widgets/community_feed_sliver.dart';
import 'widgets/community_home_filters.dart';
import 'widgets/community_home_header.dart';

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
    // 距底部不足 720 逻辑像素就预取下一页。
    _controller.attachPrefetch(
      threshold: 720,
      onLoadMore: () => ref.read(communityHomeProvider.notifier).loadMore(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(communityHomeProvider.notifier).ensureLoaded();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        ref.watch(profileProvider).value?.unreadNotificationCount ?? 0;
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
                          ? const CommunityHomeHeaderSkeleton()
                          : const SizedBox.shrink())
                    : CommunityHomeHeader(
                        state: state,
                        onAnnouncementTap: _openAnnouncement,
                      ),
              ),
            ),
            if (home != null)
              SliverToBoxAdapter(child: CommunityBoardStrip(state: state)),
            if (home != null)
              SliverToBoxAdapter(child: CommunityFilterToolbar(state: state)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              sliver: CommunityFeedSliver(state: state),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
              sliver: SliverToBoxAdapter(child: _Footer(state: state)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.home == null) return const SizedBox.shrink();
    return CommunityLoadMoreFooter(
      loading: state.loadingMore,
      error: state.loadMoreError,
      atEnd: !state.feedPage.hasMore && state.feed.isNotEmpty,
      endLabel: '已经全部看完了',
      onRetry: ref.read(communityHomeProvider.notifier).loadMore,
    );
  }
}
