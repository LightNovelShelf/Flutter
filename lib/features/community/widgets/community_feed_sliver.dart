import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/models.dart';
import '../../../shared/paging/identity_child_delegate.dart';
import '../community_providers.dart';
import 'community_feed_card.dart';
import 'community_primitives.dart';

class CommunityFeedSliver extends ConsumerWidget {
  const CommunityFeedSliver({super.key, required this.state});

  final CommunityHomeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(communityHomeProvider.notifier);

    if (state.home == null) {
      if (state.loading) return const _FeedSkeletonSliver();
      return SliverToBoxAdapter(
        child: CommunityStateCard(
          title: '无法加载社区',
          description: state.error ?? '社区暂时不可用。',
          isError: true,
          onRetry: controller.load,
        ),
      );
    }

    final Widget body;
    if (state.feed.isNotEmpty) {
      body = SliverList(delegate: _feedDelegate(state.feed));
    } else if (state.loading) {
      body = const _FeedSkeletonSliver();
    } else {
      body = const SliverToBoxAdapter(
        child: CommunityStateCard(
          title: '还没有讨论',
          description: '可以尝试其他版面或筛选条件，也可以发起第一个讨论。',
        ),
      );
    }

    final error = state.error;
    if (error == null) return body;
    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CommunityStateCard(
              title: '无法更新讨论',
              description: error,
              isError: true,
              onRetry: controller.load,
            ),
          ),
        ),
        body,
      ],
    );
  }
}

/// 帖子流子节点：只有已建好的前缀被替换才重建，翻页追加不动已有卡片。
///
/// 卡片间距用条目的顶部内边距而不是分隔子节点，追加新页时上一条末尾卡片不需要重建。
IdentityChildDelegate<CommunityFeedItem> _feedDelegate(
  List<CommunityFeedItem> feed,
) => IdentityChildDelegate<CommunityFeedItem>(
  items: feed,
  comparePrefix: true,
  itemBuilder: (context, item, index) => Padding(
    padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
    child: CommunityFeedCard(
      item: item,
      onTap: () => context.push('/community/thread/${item.id}'),
    ),
  ),
);

/// 骨架条目是常量列表，`SliverChildListDelegate` 比对同一个实例后不会重建。
class _FeedSkeletonSliver extends StatelessWidget {
  const _FeedSkeletonSliver();

  static const List<Widget> _items = <Widget>[
    CommunityFeedCardSkeleton(),
    Padding(
      padding: EdgeInsets.only(top: 8),
      child: CommunityFeedCardSkeleton(),
    ),
    Padding(
      padding: EdgeInsets.only(top: 8),
      child: CommunityFeedCardSkeleton(),
    ),
  ];

  @override
  Widget build(BuildContext context) => SliverList.list(children: _items);
}
