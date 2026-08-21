import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/community_models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/paging/paged_list.dart';
import '../../shared/paging/paged_list_controller.dart';
import 'community_providers.dart';

const int _notificationPageSize = 20;

/// 通知列表，在 [PagedListController] 的分页之上增加已读提交。
class CommunityNotificationsController
    extends PagedListController<AppNotificationItem, void> {
  CommunityNotificationsController() : super(null);

  bool _disposed = false;

  /// 同时只允许一笔已读提交，否则乐观翻转会被对账刷新覆盖。
  bool _marking = false;

  bool get hasUnread => state.items.any((item) => !item.isRead);

  @override
  void subscribe() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.watch(apiClientProvider);
  }

  @override
  int idOf(AppNotificationItem item) => item.id;

  @override
  Future<FetchedPage<AppNotificationItem>> fetchPage(int page) async {
    final result = await ref
        .read(apiClientProvider)
        .getNotifications(page: page, size: _notificationPageSize);
    return FetchedPage<AppNotificationItem>(
      items: result.items,
      page: result.page,
      totalPages: result.totalPages,
    );
  }

  @override
  String describeError(Object error) =>
      describeCommunityError(error, fallback: '无法加载通知。');

  /// 已读先本地翻转，服务端提交成功后再用列表 + 资料对齐未读角标。
  Future<void> mark(List<int> ids) async {
    if (ids.isEmpty || _marking) return;
    _marking = true;
    state = state.copyWith(
      items: state.items
          .map(
            (item) =>
                ids.contains(item.id) ? item.copyWith(isRead: true) : item,
          )
          .toList(growable: false),
    );
    try {
      await ref.read(apiClientProvider).markNotifications(ids);
    } catch (_) {
      // 返回值可能解析失败，但服务端已提交，以随后的对账为准。
    }
    if (_disposed) return;
    _marking = false;
    await Future.wait<void>(<Future<void>>[
      _reconcile(),
      ref.read(profileProvider.notifier).reload(),
    ]);
  }

  Future<void> markAll() => mark(
    state.items
        .where((item) => !item.isRead)
        .map((item) => item.id)
        .toList(growable: false),
  );

  /// 对账刷新，失败时清除错误并保留乐观结果。
  Future<void> _reconcile() async {
    await refresh();
    if (_disposed || state.error == null) return;
    state = state.copyWith(clearError: true);
  }
}

final
NotifierProvider<
  CommunityNotificationsController,
  PagedList<AppNotificationItem>
>
communityNotificationsProvider =
    NotifierProvider<
      CommunityNotificationsController,
      PagedList<AppNotificationItem>
    >(CommunityNotificationsController.new, isAutoDispose: true);
