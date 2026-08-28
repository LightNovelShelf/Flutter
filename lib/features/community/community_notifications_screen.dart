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
                description: '讨论回复和评论动态会显示在这里。',
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

/// 通知对应的目标路由，无法定位时返回 null。
String? notificationRoute(AppNotificationItem item) {
  final id = item.extra.objectId > 0 ? item.extra.objectId : item.objectId;
  switch (item.objectType) {
    case AppNotificationObjectType.communityThread:
      if (id <= 0) return null;
      final replyId = item.extra.replyId;
      // 只带 replyId，服务端会定位它所在的主楼
      return replyId == null
          ? '/community/thread/$id'
          : '/community/thread/$id?replyId=$replyId';
    case AppNotificationObjectType.book:
      if (id <= 0) return null;
      final title = item.extra.objectTitle.trim();
      return Uri(
        path: '/book/$id/comments',
        queryParameters: <String, String>{if (title.isNotEmpty) 'title': title},
      ).toString();
    case AppNotificationObjectType.announcement:
      if (id <= 0) return null;
      return '/announcement/$id';
    case AppNotificationObjectType.series:
      // 系列通知没有实体对象，只能按系列标题定位评论。
      final seriesTitle = (item.extra.seriesTitle ?? '').trim();
      if (seriesTitle.isEmpty) return null;
      return Uri(
        path: '/books/series/comments',
        queryParameters: <String, String>{'name': seriesTitle},
      ).toString();
    case AppNotificationObjectType.unknown:
      return null;
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final AppNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = !item.isRead;
    final actorName = item.actor?.userName.trim().isNotEmpty ?? false
        ? item.actor!.userName.trim()
        : '轻书架';
    final preview = item.extra.replyPreview?.trim().isNotEmpty ?? false
        ? item.extra.replyPreview!.trim()
        : item.extra.preview.trim();

    return CommunityCard(
      radius: 18,
      onTap: onTap,
      background: unread ? colors.surfaceContainerHighest : null,
      borderColor: unread ? colors.primary : null,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              UserAvatar(
                url: item.actor?.avatar ?? '',
                name: actorName,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
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
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _actionLabel(item.type),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                _typeIcon(item.objectType),
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
          if (item.extra.objectTitle.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              item.extra.objectTitle.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ],
          if (preview.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              CommunityTagPill(
                label: _objectLabel(item.objectType),
                tone: CommunityTagTone.neutral,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatRelativeTimeFine(item.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _actionLabel(AppNotificationType type) => switch (type) {
    AppNotificationType.comment => '评论了你的内容',
    AppNotificationType.commentReply => '回复了你的评论',
    AppNotificationType.communityThreadReply => '回复了你的讨论',
    AppNotificationType.communityThreadChildReply => '回复了你的社区回复',
    AppNotificationType.unknown => '向你发送了一条通知',
  };

  static String _objectLabel(AppNotificationObjectType type) => switch (type) {
    AppNotificationObjectType.communityThread => '社区',
    AppNotificationObjectType.book => '书籍',
    AppNotificationObjectType.announcement => '公告',
    AppNotificationObjectType.series => '系列',
    AppNotificationObjectType.unknown => '通知',
  };

  static IconData _typeIcon(AppNotificationObjectType type) => switch (type) {
    AppNotificationObjectType.book => Icons.menu_book_outlined,
    AppNotificationObjectType.announcement => Icons.campaign_outlined,
    _ => Icons.mode_comment_outlined,
  };
}
