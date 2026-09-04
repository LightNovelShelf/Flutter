import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/paging/paged_list.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/user_avatar.dart';
import 'community_notifications_providers.dart';
import 'widgets/community_feed_card.dart';
import 'widgets/community_primitives.dart';

class CommunityNotificationsScreen extends ConsumerStatefulWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  ConsumerState<CommunityNotificationsScreen> createState() =>
      _CommunityNotificationsScreenState();
}

class _CommunityNotificationsScreenState
    extends ConsumerState<CommunityNotificationsScreen> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.attachPrefetch(
      onLoadMore: () =>
          ref.read(communityNotificationsProvider.notifier).loadMore(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(AppNotificationItem item) {
    if (!item.isRead) {
      ref.read(communityNotificationsProvider.notifier).mark(<int>[item.id]);
    }
    final route = notificationRoute(item);
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityNotificationsProvider);
    final controller = ref.read(communityNotificationsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: <Widget>[
          if (controller.hasUnread)
            TextButton(
              onPressed: controller.markAll,
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: _buildBody(state, controller),
      ),
    );
  }

  Widget _buildBody(
    PagedList<AppNotificationItem> state,
    CommunityNotificationsController controller,
  ) {
    if (state.loading && state.items.isEmpty) {
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 11),
        itemBuilder: (_, _) => const CommunityFeedCardSkeleton(),
      );
    }
    if (state.items.isEmpty) {
      final error = state.error;
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: 1,
        itemBuilder: (_, _) => error != null
            ? CommunityStateCard(
                title: '无法加载通知',
                description: error,
                isError: true,
                onRetry: controller.retry,
              )
            : const CommunityStateCard(
                title: '没有通知',
                description: '系统消息、评论和社区回复会显示在这里。',
                icon: Icons.notifications_none,
              ),
      );
    }
    return ListView.separated(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: state.items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 11),
      itemBuilder: (_, index) {
        if (index == state.items.length) return _buildFooter(state, controller);
        final item = state.items[index];
        return _NotificationCard(item: item, onTap: () => _open(item));
      },
    );
  }

  Widget _buildFooter(
    PagedList<AppNotificationItem> state,
    CommunityNotificationsController controller,
  ) => CommunityLoadMoreFooter(
    loading: state.loadingMore,
    error: state.loadMoreError,
    atEnd: !state.hasMore,
    onRetry: controller.loadMore,
  );
}

/// 通知动作对应的目标路由；空动作、未知动作或参数错误都不跳转。
String? notificationRoute(AppNotificationItem item) {
  final action = item.action;
  if (action == null) return null;
  final data = action.data;

  switch (action.type) {
    case 'open_book':
      final bookId = _positiveInt(data['book_id']);
      return bookId == null ? null : '/book/$bookId';
    case 'open_announcement':
      final announcementId = _positiveInt(data['announcement_id']);
      return announcementId == null ? null : '/announcement/$announcementId';
    case 'open_community_thread':
      final threadId = _positiveInt(data['thread_id']);
      if (threadId == null) return null;
      final replyId = _positiveInt(data['reply_id']);
      return Uri(
        path: '/community/thread/$threadId',
        queryParameters: <String, String>{
          if (replyId != null) 'replyId': '$replyId',
        },
      ).toString();
    default:
      return null;
  }
}

int? _positiveInt(Object? value) {
  final parsed = switch (value) {
    int number => number,
    num number when number.isFinite => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };
  return parsed != null && parsed > 0 ? parsed : null;
}

typedef _TonePresentation = ({
  IconData icon,
  Color foreground,
  Color background,
});

_TonePresentation _tonePresentation(
  ColorScheme colors,
  AppNotificationTone tone,
) => switch (tone) {
  AppNotificationTone.info => (
    icon: Icons.info_outline,
    foreground: colors.primary,
    background: colors.primaryContainer.withValues(alpha: 0.45),
  ),
  AppNotificationTone.success => (
    icon: Icons.check_circle_outline,
    foreground: colors.tertiary,
    background: colors.tertiaryContainer.withValues(alpha: 0.45),
  ),
  AppNotificationTone.warning => (
    icon: Icons.warning_amber_rounded,
    foreground: const Color(0xFFF59E0B),
    background: const Color(0xFFF59E0B).withValues(alpha: 0.12),
  ),
  AppNotificationTone.danger => (
    icon: Icons.error_outline,
    foreground: colors.error,
    background: colors.errorContainer.withValues(alpha: 0.45),
  ),
  AppNotificationTone.neutral => (
    icon: Icons.notifications_none,
    foreground: colors.onSurfaceVariant,
    background: colors.surfaceContainerHighest,
  ),
};

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final AppNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = !item.isRead;
    final actor = item.actor;
    final actorName = actor?.userName.trim().isNotEmpty ?? false
        ? actor!.userName.trim()
        : '系统';
    final presentation = _tonePresentation(colors, item.tone);
    final route = notificationRoute(item);

    return CommunityCard(
      radius: 18,
      onTap: unread || route != null ? onTap : null,
      background: unread ? presentation.background : null,
      borderColor: unread ? presentation.foreground : null,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (actor == null)
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: presentation.background,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    presentation.icon,
                    size: 21,
                    color: presentation.foreground,
                  ),
                )
              else
                UserAvatar(url: actor.avatar, name: actorName, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        actorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (unread) ...<Widget>[
                      const SizedBox(width: 7),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: presentation.foreground,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatRelativeTimeFine(item.createdAt),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 15,
              height: 21 / 15,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          if (item.body.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              item.body,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (route != null) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
