import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
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

/// 目录页每页目标条数。
const int discoverPageSize = 24;

/// 多取一些，抵消本地过滤后的缺口。
const int _homeLatestFetchSize = 12;

const int _homePreviewCount = 6;

String describeApiError(Object error) {
  if (error is ApiError) {
    return switch (error.category) {
      ApiErrorCategory.auth => '登录状态已失效，请重新登录后再试。',
      ApiErrorCategory.network => '网络连接不可用，请检查网络后重试。',
      _ => error.message,
    };
  }
  if (error is RequestCancelledError) return '请求已取消。';
  return '发生了预料之外的错误，请稍后再试。';
}

/// 只订阅影响列表结果的设置项，字号变化不该触发重新拉取。
AppSettings watchContentSettings(Ref ref) {
  ref.watch(
    appSettingsProvider.select(
      (settings) => (settings.ignoreAI, settings.ignoreJapanese),
    ),
  );
  return ref.read(appSettingsProvider);
}

final AutoDisposeFutureProvider<List<BookListItem>> homeRankingProvider =
    FutureProvider.autoDispose<List<BookListItem>>((ref) async {
      final api = ref.watch(apiClientProvider);
      final period = ref.watch(
        appSettingsProvider.select((settings) => settings.homeRankType),
      );
      final settings = watchContentSettings(ref);
      final items = await api.getRank(rankPeriodDays[period]!);
      return applyContentFilter(items, settings);
    });

final AutoDisposeFutureProvider<List<BookListItem>> homeLatestBooksProvider =
    FutureProvider.autoDispose<List<BookListItem>>((ref) async {
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
    });

final AutoDisposeFutureProvider<List<BookListItem>> homeComicsProvider =
    FutureProvider.autoDispose<List<BookListItem>>((ref) async {
      final api = ref.watch(apiClientProvider);
      final page = await api.getComicList(
        page: 1,
        order: ComicOrder.latest,
        size: _homePreviewCount,
      );
      // 漫画不参与内容过滤：后端没有对应分类信息。
      return page.items.map((item) => item.toBookListItem()).toList();
    });

final AutoDisposeFutureProvider<OnlineInfo> onlineInfoProvider =
    FutureProvider.autoDispose<OnlineInfo>((ref) async {
      final api = ref.watch(apiClientProvider);
      return api.getOnlineInfo();
    });

final AutoDisposeFutureProvider<List<AnnouncementItem>>
homeAnnouncementsProvider = FutureProvider.autoDispose<List<AnnouncementItem>>((
  ref,
) async {
  final api = ref.watch(apiClientProvider);
  final page = await api.getAnnouncementList(page: 1, size: 5);
  return page.items;
});

/// 一次「可见页」拉取的结果：`page` 是实际消费到的后端页码。
class FetchedBooks {
  const FetchedBooks({
    required this.books,
    required this.page,
    required this.totalPages,
  });

  final List<BookListItem> books;
  final int page;
  final int totalPages;
}

class PagedBooks {
  const PagedBooks({
    this.books = const <BookListItem>[],
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.page = 0,
    this.totalPages = 1,
  });

  final List<BookListItem> books;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;
  final int page;
  final int totalPages;

  bool get hasMore => page > 0 && page < totalPages;

  PagedBooks copyWith({
    List<BookListItem>? books,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    int? page,
    int? totalPages,
  }) => PagedBooks(
    books: books ?? this.books,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
  );
}

/// 目录/榜单共用的分页状态机：refresh 保留旧数据，retry 清空重来。
abstract class PagedBooksController<Arg>
    extends AutoDisposeFamilyNotifier<PagedBooks, Arg> {
  int _generation = 0;
  bool _disposed = false;

  /// 订阅会让整份列表失效的依赖（API、内容过滤设置等）。
  void subscribe();

  /// 拉取一页数据；实现方可在内部连续消费多个后端页。
  Future<FetchedBooks> fetchPage(int page);

  @override
  PagedBooks build(Arg arg) {
    // build 在依赖变化时重跑，onDispose 跟着触发，所以每次都重置。
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // 离开页面后短时保活，来回切换排序/周期直接命中缓存。
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);
    subscribe();
    unawaited(Future<void>.microtask(() => _load(preserve: false)));
    return const PagedBooks();
  }

  Future<void> refresh() => _load(preserve: true);

  Future<void> retry() => _load(preserve: false);

  Future<void> _load({required bool preserve}) async {
    final generation = ++_generation;
    state = preserve
        ? state.copyWith(
            refreshing: true,
            clearError: true,
            clearLoadMoreError: true,
          )
        : const PagedBooks();
    try {
      final result = await fetchPage(1);
      if (_isStale(generation)) return;
      state = PagedBooks(
        books: result.books,
        loading: false,
        page: result.page,
        totalPages: result.totalPages,
      );
    } on RequestCancelledError {
      // 取消一定由更新的请求发起，收尾交给那个请求。
    } catch (error) {
      if (_isStale(generation)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: describeApiError(error),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current.loading || current.refreshing || current.loadingMore) return;
    if (!current.hasMore) return;
    final generation = ++_generation;
    state = current.copyWith(loadingMore: true, clearLoadMoreError: true);
    try {
      final result = await fetchPage(current.page + 1);
      if (_isStale(generation)) return;
      final merged = List<BookListItem>.of(state.books);
      final seen = merged.map((book) => book.id).toSet();
      for (final book in result.books) {
        if (seen.add(book.id)) merged.add(book);
      }
      state = state.copyWith(
        books: merged,
        loadingMore: false,
        page: result.page,
        totalPages: result.totalPages,
      );
    } on RequestCancelledError {
      // 同上。
    } catch (error) {
      if (_isStale(generation)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeApiError(error),
      );
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}

class BookCatalogController extends PagedBooksController<BookListOrder> {
  @override
  void subscribe() {
    ref.watch(apiClientProvider);
    watchContentSettings(ref);
  }

  @override
  Future<FetchedBooks> fetchPage(int page) async {
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
    return FetchedBooks(
      books: collected,
      page: current,
      totalPages: totalPages,
    );
  }
}

class ComicCatalogController extends PagedBooksController<ComicOrder> {
  @override
  void subscribe() {
    ref.watch(apiClientProvider);
  }

  @override
  Future<FetchedBooks> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final response = await api.getComicList(
      page: page,
      order: arg,
      size: discoverPageSize,
    );
    return FetchedBooks(
      books: response.items.map((item) => item.toBookListItem()).toList(),
      page: page,
      totalPages: response.totalPages,
    );
  }
}

/// 榜单接口一次返回完整列表，没有分页。
class RankingController extends PagedBooksController<HomeRankType> {
  @override
  void subscribe() {
    ref.watch(apiClientProvider);
    watchContentSettings(ref);
  }

  @override
  Future<FetchedBooks> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final settings = ref.read(appSettingsProvider);
    final items = await api.getRank(rankPeriodDays[arg]!);
    return FetchedBooks(
      books: applyContentFilter(items, settings),
      page: 1,
      totalPages: 1,
    );
  }
}

final AutoDisposeNotifierProviderFamily<
  BookCatalogController,
  PagedBooks,
  BookListOrder
>
bookCatalogProvider = NotifierProvider.autoDispose
    .family<BookCatalogController, PagedBooks, BookListOrder>(
      BookCatalogController.new,
    );

final AutoDisposeNotifierProviderFamily<
  ComicCatalogController,
  PagedBooks,
  ComicOrder
>
comicCatalogProvider = NotifierProvider.autoDispose
    .family<ComicCatalogController, PagedBooks, ComicOrder>(
      ComicCatalogController.new,
    );

final AutoDisposeNotifierProviderFamily<
  RankingController,
  PagedBooks,
  HomeRankType
>
rankingProvider = NotifierProvider.autoDispose
    .family<RankingController, PagedBooks, HomeRankType>(RankingController.new);

class PagedAnnouncements {
  const PagedAnnouncements({
    this.items = const <AnnouncementItem>[],
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.page = 0,
    this.totalPages = 1,
  });

  final List<AnnouncementItem> items;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;
  final int page;
  final int totalPages;

  bool get hasMore => page > 0 && page < totalPages;

  PagedAnnouncements copyWith({
    List<AnnouncementItem>? items,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    int? page,
    int? totalPages,
  }) => PagedAnnouncements(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
  );
}

class AnnouncementCenterController
    extends AutoDisposeNotifier<PagedAnnouncements> {
  int _generation = 0;
  bool _disposed = false;

  @override
  PagedAnnouncements build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.watch(apiClientProvider);
    unawaited(Future<void>.microtask(() => _load(preserve: false)));
    return const PagedAnnouncements();
  }

  Future<void> refresh() => _load(preserve: true);

  Future<void> retry() => _load(preserve: false);

  Future<void> _load({required bool preserve}) async {
    final generation = ++_generation;
    state = preserve
        ? state.copyWith(
            refreshing: true,
            clearError: true,
            clearLoadMoreError: true,
          )
        : const PagedAnnouncements();
    try {
      final page = await ref
          .read(apiClientProvider)
          .getAnnouncementList(page: 1, size: discoverPageSize);
      if (_isStale(generation)) return;
      state = PagedAnnouncements(
        items: page.items,
        loading: false,
        page: 1,
        totalPages: page.totalPages,
      );
    } on RequestCancelledError {
      // 交给更新的请求收尾。
    } catch (error) {
      if (_isStale(generation)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: describeApiError(error),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current.loading || current.refreshing || current.loadingMore) return;
    if (!current.hasMore) return;
    final generation = ++_generation;
    final nextPage = current.page + 1;
    state = current.copyWith(loadingMore: true, clearLoadMoreError: true);
    try {
      final page = await ref
          .read(apiClientProvider)
          .getAnnouncementList(page: nextPage, size: discoverPageSize);
      if (_isStale(generation)) return;
      final merged = List<AnnouncementItem>.of(state.items);
      final seen = merged.map((item) => item.id).toSet();
      for (final item in page.items) {
        if (seen.add(item.id)) merged.add(item);
      }
      state = state.copyWith(
        items: merged,
        loadingMore: false,
        page: nextPage,
        totalPages: page.totalPages,
      );
    } on RequestCancelledError {
      // 同上。
    } catch (error) {
      if (_isStale(generation)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeApiError(error),
      );
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}

final AutoDisposeNotifierProvider<
  AnnouncementCenterController,
  PagedAnnouncements
>
announcementCenterProvider =
    NotifierProvider.autoDispose<
      AnnouncementCenterController,
      PagedAnnouncements
    >(AnnouncementCenterController.new);

final AutoDisposeFutureProviderFamily<AnnouncementItem, int>
announcementDetailProvider = FutureProvider.autoDispose
    .family<AnnouncementItem, int>((ref, id) async {
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
    });
