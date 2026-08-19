import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/community_models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';
import 'community_providers.dart';
import 'widgets/community_widgets.dart';

const int _notificationPageSize = 20;

class CommunityNotificationsScreen extends ConsumerStatefulWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  ConsumerState<CommunityNotificationsScreen> createState() =>
      _CommunityNotificationsScreenState();
}

class _CommunityNotificationsScreenState
    extends ConsumerState<CommunityNotificationsScreen> {
  final ScrollController _controller = ScrollController();

  List<AppNotificationItem> _items = const <AppNotificationItem>[];
  int _page = 1;
  int _totalPages = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _marking = false;
  String? _error;
  String? _loadMoreError;
  int _operation = 0;

  bool get _hasUnread => _items.any((item) => !item.isRead);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter < 480) _loadMore();
  }

  Future<void> _load({bool silent = false}) async {
    final token = ++_operation;
    if (!silent) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
        _loadMoreError = null;
      });
    }
    try {
      final page = await ref.read(apiClientProvider).getNotifications(
            page: 1,
            size: _notificationPageSize,
          );
      if (!mounted || token != _operation) return;
      setState(() {
        _items = page.items;
        _page = page.page;
        _totalPages = page.totalPages;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || token != _operation) return;
      setState(() {
        _loading = false;
        if (!silent) {
          _error = describeCommunityError(error, fallback: '无法加载通知。');
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _page >= _totalPages) return;
    final token = _operation;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await ref.read(apiClientProvider).getNotifications(
            page: _page + 1,
            size: _notificationPageSize,
          );
      if (!mounted || token != _operation) return;
      setState(() {
        _items = mergeCommunityById(_items, page.items, (item) => item.id);
        _page = page.page;
        _totalPages = page.totalPages;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || token != _operation) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = describeCommunityError(error, fallback: '无法加载更多通知。');
      });
    }
  }

  /// 已读先本地翻转，服务端提交成功后再用列表 + 资料对齐未读角标。
  Future<void> _mark(List<int> ids) async {
    if (ids.isEmpty || _marking) return;
    setState(() {
      _marking = true;
      _items = _items
          .map((item) => ids.contains(item.id) ? item.copyWith(isRead: true) : item)
          .toList(growable: false);
    });
    try {
      await ref.read(apiClientProvider).markNotifications(ids);
    } catch (_) {
      // 服务端其实已提交，只是返回值解不出来，交给随后的对账。
    }
    if (!mounted) return;
    setState(() => _marking = false);
    await Future.wait<void>(<Future<void>>[
      _load(silent: true),
      ref.read(profileProvider.notifier).reload(),
    ]);
  }

  Future<void> _markAll() => _mark(
        _items
            .where((item) => !item.isRead)
            .map((item) => item.id)
            .toList(growable: false),
      );

  void _open(AppNotificationItem item) {
    if (!item.isRead) _mark(<int>[item.id]);
    final id = item.extra.objectId > 0 ? item.extra.objectId : item.objectId;
    if (id <= 0) return;
    switch (item.objectType) {
      case AppNotificationObjectType.communityThread:
        final query = <String, String>{
          if (item.extra.parentReplyId != null)
            'parentReplyId': '${item.extra.parentReplyId}',
          if (item.extra.replyId != null) 'replyId': '${item.extra.replyId}',
        };
        context.push(
          query.isEmpty
              ? '/community/thread/$id'
              : Uri(
                  path: '/community/thread/$id',
                  queryParameters: query,
                ).toString(),
        );
      case AppNotificationObjectType.book:
        context.push(
          Uri(
            path: '/book/$id/comments',
            queryParameters: <String, String>{
              'title': item.extra.objectTitle.trim().isEmpty
                  ? '评论'
                  : item.extra.objectTitle.trim(),
              'target': 'Book',
            },
          ).toString(),
        );
      case AppNotificationObjectType.announcement:
        context.push('/announcement/$id');
      case AppNotificationObjectType.series:
      case AppNotificationObjectType.unknown:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: <Widget>[
          if (_hasUnread)
            TextButton(
              onPressed: _marking ? null : _markAll,
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 11),
        itemBuilder: (_, _) => const CommunityFeedCardSkeleton(),
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          if (_error != null)
            CommunityStateCard(
              title: '无法加载通知',
              description: _error!,
              isError: true,
              onRetry: _load,
            )
          else
            const CommunityStateCard(
              title: '没有通知',
              description: '讨论回复和评论动态会显示在这里。',
              icon: Icons.notifications_none,
            ),
        ],
      );
    }
    return ListView.separated(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 11),
      itemBuilder: (_, index) {
        if (index == _items.length) return _buildFooter();
        final item = _items[index];
        return _NotificationCard(item: item, onTap: () => _open(item));
      },
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    if (_loadMoreError != null) {
      return CommunityStateCard(
        title: '无法加载更多',
        description: _loadMoreError!,
        isError: true,
        onRetry: _loadMore,
      );
    }
    if (_page < _totalPages) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: OutlinedButton(onPressed: _loadMore, child: const Text('加载更多')),
        ),
      );
    }
    return const SizedBox(height: 8);
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
              CommunityAvatar(
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
                  formatCommunityTime(item.createdAt),
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
