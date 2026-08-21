import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/content_filter.dart';
import '../../shared/paging/paged_list.dart';
import '../../shared/paging/paged_list_controller.dart';
import 'home_providers.dart';

/// 目录页每页目标条数。
const int discoverPageSize = 24;

/// 离开页面后的保活时长，用于切换排序或周期时命中缓存。
const Duration _catalogKeepAlive = Duration(minutes: 5);

class BookCatalogController
    extends PagedListController<BookListItem, BookListOrder> {
  BookCatalogController(super.arg);

  @override
  Duration? get keepAliveFor => _catalogKeepAlive;

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
    watchContentSettings(ref);
  }

  @override
  int idOf(BookListItem book) => book.id;

  @override
  Future<FetchedPage<BookListItem>> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final settings = ref.read(appSettingsProvider);
    final collected = <BookListItem>[];
    final seen = <int>{};
    var current = page;
    var totalPages = 1;
    while (true) {
      final response = await api.getBookList(
        page: current,
        size: discoverPageSize,
        order: arg,
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      totalPages = response.totalPages;
      for (final book in applyContentFilter(response.items, settings)) {
        if (seen.add(book.id)) collected.add(book);
      }
      // 本地补充过滤后若不足一页，继续取下一页。
      if (response.items.isEmpty ||
          collected.length >= discoverPageSize ||
          current >= totalPages) {
        break;
      }
      current += 1;
    }
    return FetchedPage<BookListItem>(
      items: collected,
      page: current,
      totalPages: totalPages,
    );
  }
}

/// 系列内书籍列表的参数：系列名与排序。
typedef SeriesBooksArg = ({String name, BookListOrder order});

/// 全部小说的按系列视图，每页一页系列，不做本地补充过滤。
class NovelSeriesCatalogController
    extends PagedListController<NovelSeriesListItem, BookListOrder> {
  NovelSeriesCatalogController(super.arg);

  @override
  Duration? get keepAliveFor => _catalogKeepAlive;

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
    watchContentSettings(ref);
  }

  /// 系列没有数字 id，分组键即系列名。
  @override
  Object idOf(NovelSeriesListItem series) => series.name;

  @override
  Future<FetchedPage<NovelSeriesListItem>> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final settings = ref.read(appSettingsProvider);
    final response = await api.getNovelSeriesList(
      page: page,
      size: discoverPageSize,
      order: arg,
      ignoreJapanese: settings.ignoreJapanese,
      ignoreAI: settings.ignoreAI,
    );
    return FetchedPage<NovelSeriesListItem>(
      items: response.items,
      page: page,
      totalPages: response.totalPages,
    );
  }
}

/// 单个系列下的全部小说，不做过滤后补页的循环。
class SeriesBooksController
    extends PagedListController<BookListItem, SeriesBooksArg> {
  SeriesBooksController(super.arg);

  @override
  Duration? get keepAliveFor => _catalogKeepAlive;

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
    watchContentSettings(ref);
  }

  @override
  Object idOf(BookListItem book) => book.id;

  @override
  Future<FetchedPage<BookListItem>> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final settings = ref.read(appSettingsProvider);
    final response = await api.getBooksBySeries(
      seriesName: arg.name,
      page: page,
      size: discoverPageSize,
      order: arg.order,
      ignoreJapanese: settings.ignoreJapanese,
      ignoreAI: settings.ignoreAI,
    );
    return FetchedPage<BookListItem>(
      items: applyContentFilter(response.items, settings),
      page: page,
      totalPages: response.totalPages,
    );
  }
}

class ComicCatalogController
    extends PagedListController<BookListItem, ComicOrder> {
  ComicCatalogController(super.arg);

  @override
  Duration? get keepAliveFor => _catalogKeepAlive;

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
  }

  @override
  int idOf(BookListItem book) => book.id;

  @override
  Future<FetchedPage<BookListItem>> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final response = await api.getComicList(
      page: page,
      order: arg,
      size: discoverPageSize,
    );
    return FetchedPage<BookListItem>(
      items: response.items.map((item) => item.toBookListItem()).toList(),
      page: page,
      totalPages: response.totalPages,
    );
  }
}

/// 榜单接口一次返回完整列表，没有分页。
class RankingController
    extends PagedListController<BookListItem, HomeRankType> {
  RankingController(super.arg);

  @override
  Duration? get keepAliveFor => _catalogKeepAlive;

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
    watchContentSettings(ref);
  }

  @override
  int idOf(BookListItem book) => book.id;

  @override
  Future<FetchedPage<BookListItem>> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final settings = ref.read(appSettingsProvider);
    final items = await api.getRank(rankPeriodDays[arg]!);
    return FetchedPage<BookListItem>(
      items: applyContentFilter(items, settings),
      page: 1,
      totalPages: 1,
    );
  }
}

final
NotifierProviderFamily<
  BookCatalogController,
  PagedList<BookListItem>,
  BookListOrder
>
bookCatalogProvider =
    NotifierProvider.family<
      BookCatalogController,
      PagedList<BookListItem>,
      BookListOrder
    >(BookCatalogController.new, isAutoDispose: true);

final
NotifierProviderFamily<
  NovelSeriesCatalogController,
  PagedList<NovelSeriesListItem>,
  BookListOrder
>
novelSeriesCatalogProvider =
    NotifierProvider.family<
      NovelSeriesCatalogController,
      PagedList<NovelSeriesListItem>,
      BookListOrder
    >(NovelSeriesCatalogController.new, isAutoDispose: true);

final
NotifierProviderFamily<
  SeriesBooksController,
  PagedList<BookListItem>,
  SeriesBooksArg
>
seriesBooksProvider =
    NotifierProvider.family<
      SeriesBooksController,
      PagedList<BookListItem>,
      SeriesBooksArg
    >(SeriesBooksController.new, isAutoDispose: true);

final
NotifierProviderFamily<
  ComicCatalogController,
  PagedList<BookListItem>,
  ComicOrder
>
comicCatalogProvider =
    NotifierProvider.family<
      ComicCatalogController,
      PagedList<BookListItem>,
      ComicOrder
    >(ComicCatalogController.new, isAutoDispose: true);

final
NotifierProviderFamily<
  RankingController,
  PagedList<BookListItem>,
  HomeRankType
>
rankingProvider =
    NotifierProvider.family<
      RankingController,
      PagedList<BookListItem>,
      HomeRankType
    >(RankingController.new, isAutoDispose: true);
