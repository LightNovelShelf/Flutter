import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/content_filter.dart';

const Map<HomeRankType, int> rankPeriodDays = <HomeRankType, int>{
  HomeRankType.daily: 1,
  HomeRankType.weekly: 7,
  HomeRankType.monthly: 31,
};

const Map<HomeRankType, String> rankPeriodLabels = <HomeRankType, String>{
  HomeRankType.daily: '日榜',
  HomeRankType.weekly: '周榜',
  HomeRankType.monthly: '月榜',
};

/// 多取一些，抵消本地过滤后的缺口。
const int _homeLatestFetchSize = 12;

const int _homePreviewCount = 6;

/// 只订阅影响列表结果的设置项，字号变化不该触发重新拉取。
AppSettings watchContentSettings(Ref ref) {
  ref.watch(
    appSettingsProvider.select(
      (settings) => (settings.ignoreAI, settings.ignoreJapanese),
    ),
  );
  return ref.read(appSettingsProvider);
}

final FutureProvider<List<BookListItem>> homeRankingProvider =
    FutureProvider<List<BookListItem>>((ref) async {
      final api = ref.watch(apiClientProvider);
      final period = ref.watch(
        appSettingsProvider.select((settings) => settings.homeRankType),
      );
      final settings = watchContentSettings(ref);
      final items = await api.getRank(rankPeriodDays[period]!);
      return applyContentFilter(items, settings);
    }, isAutoDispose: true);

final FutureProvider<List<BookListItem>> homeLatestBooksProvider =
    FutureProvider<List<BookListItem>>((ref) async {
      final api = ref.watch(apiClientProvider);
      final settings = watchContentSettings(ref);
      final page = await api.getBookList(
        page: 1,
        size: _homeLatestFetchSize,
        order: BookListOrder.latest,
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      final filtered = applyContentFilter(page.items, settings);
      return filtered.take(_homePreviewCount).toList();
    }, isAutoDispose: true);

final FutureProvider<List<BookListItem>> homeComicsProvider =
    FutureProvider<List<BookListItem>>((ref) async {
      final api = ref.watch(apiClientProvider);
      final page = await api.getComicList(
        page: 1,
        order: ComicOrder.latest,
        size: _homePreviewCount,
      );
      // 漫画不参与内容过滤：后端没有对应分类信息。
      return page.items.map((item) => item.toBookListItem()).toList();
    }, isAutoDispose: true);

final FutureProvider<OnlineInfo> onlineInfoProvider =
    FutureProvider<OnlineInfo>((ref) async {
      final api = ref.watch(apiClientProvider);
      return api.getOnlineInfo();
    }, isAutoDispose: true);

final FutureProvider<List<AnnouncementItem>> homeAnnouncementsProvider =
    FutureProvider<List<AnnouncementItem>>((ref) async {
      final api = ref.watch(apiClientProvider);
      final page = await api.getAnnouncementList(page: 1, size: 5);
      return page.items;
    }, isAutoDispose: true);
