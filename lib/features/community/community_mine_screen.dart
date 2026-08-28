import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import 'widgets/community_feed_card.dart';
import 'widgets/community_primitives.dart';

enum _MineTab { published, participated, favorites }

/// 我的社区：发布 / 参与 / 收藏三组，共用一次总览请求。
class MyCommunityScreen extends ConsumerStatefulWidget {
  const MyCommunityScreen({super.key});

  @override
  ConsumerState<MyCommunityScreen> createState() => _MyCommunityScreenState();
}

class _MyCommunityScreenState extends ConsumerState<MyCommunityScreen> {
  CommunityMyOverview? _overview;
  _MineTab _tab = _MineTab.published;
  bool _loading = true;
  String? _error;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = ++_operation;
    setState(() {
      _loading = _overview == null;
      _error = null;
    });
    try {
      final overview = await ref
          .read(apiClientProvider)
          .getMyCommunityOverview();
      if (!mounted || token != _operation) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _operation) return;
      setState(() {
        _loading = false;
        _error = '无法加载“我的社区”。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Scaffold(
      appBar: AppBar(title: const Text('我的社区')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: overview == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 44),
                children: <Widget>[
                  if (_loading)
                    const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    CommunityStateCard(
                      title: '无法加载“我的社区”',
                      description: _error ?? '无法加载“我的社区”。',
                      isError: true,
                      onRetry: _load,
                    ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 44),
                itemCount: _sectionCount(overview) + 1,
                itemBuilder: (_, index) => index == 0
                    ? _header(overview)
                    : _sectionItem(overview, index - 1),
              ),
      ),
    );
  }

  /// 列表首格：资料卡与分页按钮。
  ///
  /// `stretch` 保住原来直接放在 ListView 里时的满宽约束。
  Widget _header(CommunityMyOverview overview) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _ProfileCard(overview: overview),
      const SizedBox(height: 16),
      SegmentedButton<_MineTab>(
        segments: const <ButtonSegment<_MineTab>>[
          ButtonSegment<_MineTab>(
            value: _MineTab.published,
            label: Text('已发布'),
          ),
          ButtonSegment<_MineTab>(
            value: _MineTab.participated,
            label: Text('已参与'),
          ),
          ButtonSegment<_MineTab>(value: _MineTab.favorites, label: Text('收藏')),
        ],
        selected: <_MineTab>{_tab},
        onSelectionChanged: _loading
            ? null
            : (selection) => setState(() => _tab = selection.first),
      ),
      const SizedBox(height: 16),
    ],
  );

  /// 空态也占一格，用来显示状态卡。
  int _sectionCount(CommunityMyOverview overview) {
    final int length = switch (_tab) {
      _MineTab.published => overview.publishedThreads.length,
      _MineTab.favorites => overview.favoriteThreads.length,
      _MineTab.participated => overview.participatedReplies.length,
    };
    return length == 0 ? 1 : length;
  }

  Widget _sectionItem(CommunityMyOverview overview, int index) {
    switch (_tab) {
      case _MineTab.published:
        return _threadItem(
          overview.publishedThreads,
          index,
          emptyTitle: '还没有发布讨论',
          emptyDescription: '你发布的讨论会显示在这里。',
        );
      case _MineTab.favorites:
        return _threadItem(
          overview.favoriteThreads,
          index,
          emptyTitle: '还没有收藏',
          emptyDescription: '你收藏的讨论会显示在这里。',
        );
      case _MineTab.participated:
        final List<CommunityMyReplyItem> replies = overview.participatedReplies;
        if (replies.isEmpty) {
          return const CommunityStateCard(
            title: '还没有参与的讨论',
            description: '你在社区讨论中发布的回复会显示在这里。',
            icon: Icons.mode_comment_outlined,
          );
        }
        final CommunityMyReplyItem reply = replies[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _MyReplyCard(
            reply: reply,
            // 深链带 replyId，服务端把它所在主楼置顶，帖子页直接高亮定位。
            onTap: () => context.push(
              '/community/thread/${reply.threadId}?replyId=${reply.id}',
            ),
          ),
        );
    }
  }

  Widget _threadItem(
    List<CommunityFeedItem> items,
    int index, {
    required String emptyTitle,
    required String emptyDescription,
  }) {
    if (items.isEmpty) {
      return CommunityStateCard(
        title: emptyTitle,
        description: emptyDescription,
        icon: Icons.forum_outlined,
      );
    }
    final CommunityFeedItem item = items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CommunityFeedCard(
        item: item,
        onTap: () => context.push('/community/thread/${item.id}'),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.overview});

  final CommunityMyOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = overview.authorName.trim().isEmpty
        ? '我的社区'
        : overview.authorName.trim();
    return CommunityCard(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${formatCount(overview.publishedThreads.length)} 篇发布'
            ' · ${formatCount(overview.participatedReplies.length)} 条回复'
            ' · ${formatCount(overview.favoriteThreads.length)} 个收藏',
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MyReplyCard extends StatelessWidget {
  const _MyReplyCard({required this.reply, required this.onTap});

  final CommunityMyReplyItem reply;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final replyToName = reply.replyToName?.trim() ?? '';
    return CommunityCard(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (reply.boardName.trim().isNotEmpty)
                CommunityTagPill(label: reply.boardName.trim()),
              const Spacer(),
              Text(
                formatRelativeTimeFine(reply.publishedAt),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            reply.threadTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              height: 21 / 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          if (replyToName.isNotEmpty) ...<Widget>[
            const SizedBox(height: 9),
            Text(
              '回复 $replyToName',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
          const SizedBox(height: 9),
          Text(
            reply.content.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 21 / 14,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Icon(
                Icons.mode_comment_outlined,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                '打开讨论',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.favorite_border,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                formatCompactCount(reply.likes),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
