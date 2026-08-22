import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import 'community_providers.dart';
import 'widgets/community_primitives.dart';
import 'widgets/community_rank_panels.dart';

/// 排行榜读社区首页缓存，用户主动刷新时才回源。
class CommunityRankingsScreen extends ConsumerStatefulWidget {
  const CommunityRankingsScreen({super.key});

  @override
  ConsumerState<CommunityRankingsScreen> createState() =>
      _CommunityRankingsScreenState();
}

class _CommunityRankingsScreenState
    extends ConsumerState<CommunityRankingsScreen> {
  bool _refreshing = false;
  String? _error;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final payload = await ref
          .read(apiClientProvider)
          .getCommunityHome(
            const CommunityListQuery(page: 1, size: communityPageSize),
          );
      if (!mounted) return;
      ref.read(communityHomeCacheProvider.notifier).publish(payload);
      setState(() => _refreshing = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = describeCommunityError(error, fallback: '无法刷新排行榜。');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final payload = ref.watch(communityHomeCacheProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        actions: <Widget>[
          IconButton(
            onPressed: _refreshing ? null : _refresh,
            tooltip: '刷新',
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 44),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              CommunityStateCard(
                title: '无法刷新排行榜',
                description: _error!,
                isError: true,
                onRetry: _refresh,
              ),
              const SizedBox(height: 16),
            ],
            if (payload == null)
              Padding(
                padding: const EdgeInsets.only(top: 96),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.local_fire_department_outlined,
                      size: 26,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '这里还没有内容',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        '打开“社区”标签页后，即可加载热门讨论和活跃成员。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 19 / 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              if (payload.hotThreads.isNotEmpty) ...<Widget>[
                CommunityHotThreadsPanel(
                  items: payload.hotThreads,
                  onOpen: (id) => context.push('/community/thread/$id'),
                ),
                const SizedBox(height: 16),
              ],
              if (payload.activeUsers.isNotEmpty)
                CommunityActiveUsersPanel(users: payload.activeUsers),
              if (payload.hotThreads.isEmpty && payload.activeUsers.isEmpty)
                const CommunityStateCard(
                  title: '暂无榜单数据',
                  description: '社区活跃度还没有累积到足够的数据。',
                  icon: Icons.leaderboard_outlined,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
