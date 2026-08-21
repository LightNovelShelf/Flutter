import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/community_models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/paging/paged_list.dart';
import '../../shared/paging/paged_list_controller.dart';
import 'community_providers.dart';

const int _notificationPageSize = 20;

/// 通知列表：分页部分完全交给 [PagedListController]，只额外挂已读提交。
class CommunityNotificationsController
    extends PagedListController<AppNotificationItem, void> {
  CommunityNotificationsController() : super(null);

  bool _disposed = false;

  /// 一次只允许一笔已读提交，否则乐观翻转会和对账刷新打架。
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
      // 服务端其实已提交，只是返回值解不出来，交给随后的对账。
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

  /// 对账刷新：失败就沉默，页面上留着刚翻转好的乐观结果，不该再弹错误条。
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
