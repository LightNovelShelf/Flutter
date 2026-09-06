import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/user_avatar.dart';
import 'direct_message_providers.dart';

/// 私信会话列表。
class DirectMessageListScreen extends ConsumerStatefulWidget {
  const DirectMessageListScreen({super.key});

  @override
  ConsumerState<DirectMessageListScreen> createState() =>
      _DirectMessageListScreenState();
}

class _DirectMessageListScreenState
    extends ConsumerState<DirectMessageListScreen>
    with WidgetsBindingObserver {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.attachPrefetch(
      onLoadMore: () =>
          ref.read(directConversationListProvider.notifier).loadMore(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(directConversationListProvider.notifier).refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(directConversationListProvider);
    final controller = ref.read(directConversationListProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('私信')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: _buildBody(state, controller),
      ),
    );
  }

  Widget _buildBody(
    DirectConversationListState state,
    DirectConversationListController controller,
  ) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      final error = state.error;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
          if (error != null)
            ErrorStateView(message: error, onRetry: controller.retry)
          else
            const EmptyStateView(
              icon: Icons.forum_outlined,
              title: '还没有私信',
              description: '在网页端或对方主动发起后，会话会显示在这里。',
            ),
        ],
      );
    }
    return ListView.separated(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.items.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (_, index) {
        if (index == state.items.length) {
          return ListFooterStatus(
            loading: state.loadingMore,
            hasMore: state.hasMore,
            endLabel: '没有更多会话了',
            error: state.loadMoreError,
            onRetry: controller.loadMore,
          );
        }
        final item = state.items[index];
        return _ConversationTile(
          item: item,
          onTap: () => context.push('/messages/${item.peer.id}'),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.item, required this.onTap});

  final DirectConversationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final peer = item.peer;
    final name = displayUserName(peer.userName, deleted: peer.isDeleted);
    final preview = item.lastMessage.content.replaceAll('\n', ' ');

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      leading: UserAvatar(url: peer.avatar, name: name, size: 48),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatRelativeTime(item.lastMessage.createdAt),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            if (item.isBlockedByMe) ...<Widget>[
              const SizedBox(width: 8),
              Icon(Icons.block, size: 14, color: colors.onSurfaceVariant),
            ],
            if (item.unreadCount > 0) ...<Widget>[
              const SizedBox(width: 8),
              _UnreadDot(count: item.unreadCount),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: colors.onError,
        ),
      ),
    );
  }
}
