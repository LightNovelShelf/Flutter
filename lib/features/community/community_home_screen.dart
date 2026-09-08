import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/profile_repository.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/unread_badge.dart';
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
  late final TextEditingController _searchInput;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchInput = TextEditingController(
      text: ref.read(communityHomeProvider).query.keyWords,
    );
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
    _searchInput.dispose();
    _searchFocus.dispose();
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

  void _submitSearch(String value) {
    final keyWords = value.trim();
    _searchInput.value = TextEditingValue(
      text: keyWords,
      selection: TextSelection.collapsed(offset: keyWords.length),
    );
    _searchFocus.unfocus();
    if (_controller.hasClients) _controller.jumpTo(0);
    ref.read(communityHomeProvider.notifier).submitSearch(keyWords);
  }

  Widget _buildSearchField(CommunityHomeState state) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchInput,
      builder: (context, value, _) => Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _searchInput,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                hintText: '搜索标题或摘要',
                isDense: true,
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: value.text.isEmpty && state.query.keyWords.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '清空搜索',
                        onPressed: () => _submitSearch(''),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _submitSearch(_searchInput.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityHomeProvider);
    ref.listen<String>(
      communityHomeProvider.select((state) => state.query.keyWords),
      (previous, next) {
        if (_searchInput.text == next) return;
        _searchInput.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );
    final profile = ref.watch(profileProvider).value;
    final unreadNotifications = profile?.unreadNotificationCount ?? 0;
    final unreadMessages = profile?.unreadDirectMessageCount ?? 0;
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
                  onPressed: () => context.push('/messages'),
                  tooltip: '私信',
                  icon: UnreadBadge(
                    count: unreadMessages,
                    child: const Icon(Icons.mail_outline),
                  ),
                ),
                IconButton(
                  onPressed: () => context.push('/community/notifications'),
                  tooltip: '通知',
                  icon: UnreadBadge(
                    count: unreadNotifications,
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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              sliver: SliverToBoxAdapter(child: _buildSearchField(state)),
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
