import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/paging/paged_list.dart';
import '../../shared/paging/paged_list_controller.dart';
import '../discover/catalog_providers.dart';

/// 公告中心没有筛选维度，`arg` 恒为 null。
class AnnouncementCenterController
    extends PagedListController<AnnouncementItem, void> {
  AnnouncementCenterController() : super(null);

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
  }

  @override
  int idOf(AnnouncementItem item) => item.id;

  @override
  Future<FetchedPage<AnnouncementItem>> fetchPage(int page) async {
    final result = await ref
        .read(apiClientProvider)
        .getAnnouncementList(page: page, size: discoverPageSize);
    return FetchedPage<AnnouncementItem>(
      items: result.items,
      page: page,
      totalPages: result.totalPages,
    );
  }
}

final
NotifierProvider<AnnouncementCenterController, PagedList<AnnouncementItem>>
announcementCenterProvider =
    NotifierProvider<
      AnnouncementCenterController,
      PagedList<AnnouncementItem>
    >(AnnouncementCenterController.new, isAutoDispose: true);

final FutureProviderFamily<AnnouncementItem, int> announcementDetailProvider =
    FutureProvider.family<AnnouncementItem, int>((ref, id) async {
      // 非法 id 直接短路，避免拿一条无关公告糊弄用户。
      if (id <= 0) {
        throw const ApiError('公告地址无效。', ApiErrorCategory.unknown);
      }
      final detail = await ref
          .watch(apiClientProvider)
          .getAnnouncementDetail(id);
      if (detail.id != id) {
        throw const ApiError('公告地址无效。', ApiErrorCategory.unknown);
      }
      return detail;
    }, isAutoDispose: true);
