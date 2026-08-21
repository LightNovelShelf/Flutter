import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async/serial_queue.dart';
import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/content_filter.dart';
import '../../shared/paging/paged_list.dart';

const String searchHistoryStorageKey = 'lightnovel.search-history.v1';
const int _historyLimit = 10;
const int _searchPageSize = 24;
const Duration searchDebounce = Duration(milliseconds: 350);

/// 搜索历史：最近在前、去重、限 10 条。
class SearchHistoryController extends AsyncNotifier<List<String>> {
  final SerialQueue _writes = SerialQueue();

  @override
  Future<List<String>> build() async {
    final raw = await ref
        .read(appRuntimeProvider)
        .keyValueStore
        .read(searchHistoryStorageKey);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return _normalize(decoded.whereType<String>());
    } catch (_) {
      return const <String>[];
    }
  }

  static List<String> _normalize(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      result.add(trimmed);
      if (result.length >= _historyLimit) break;
    }
    return result;
  }

  /// 写盘串行且不阻塞搜索，失败忽略。
  void _persist(List<String> values) {
    final store = ref.read(appRuntimeProvider).keyValueStore;
    _writes
        .add(() => store.write(searchHistoryStorageKey, jsonEncode(values)))
        .ignore();
  }

  void _apply(List<String> values) {
    state = AsyncValue<List<String>>.data(values);
    _persist(values);
  }

  void add(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    _apply(_normalize(<String>[trimmed, ...state.value ?? <String>[]]));
  }

  void remove(String keyword) {
    final current = state.value;
    if (current == null) return;
    _apply(current.where((value) => value != keyword).toList());
  }

  void clear() => _apply(const <String>[]);
}

final AsyncNotifierProvider<SearchHistoryController, List<String>>
searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryController, List<String>>(
      SearchHistoryController.new,
    );

@immutable
class BookSearchState {
  const BookSearchState({
    required this.query,
    required this.mode,
    required this.comic,
    required this.items,
    required this.page,
    required this.totalPages,
    required this.loading,
    required this.loadingMore,
    this.error,
  });

  const BookSearchState.initial()
    : query = '',
      mode = BookSearchMode.fuzzy,
      comic = false,
      items = const <BookListItem>[],
      page = 1,
      totalPages = 1,
      loading = false,
      loadingMore = false,
      error = null;

  /// 已提交的关键词，为空表示尚未搜索。
  final String query;
  final BookSearchMode mode;
  final bool comic;
  final List<BookListItem> items;
  final int page;
  final int totalPages;
  final bool loading;
  final bool loadingMore;
  final String? error;

  bool get hasMore => page < totalPages;
  bool get isIdle => query.isEmpty;

  BookSearchState copyWith({
    String? query,
    BookSearchMode? mode,
    bool? comic,
    List<BookListItem>? items,
    int? page,
    int? totalPages,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
  }) => BookSearchState(
    query: query ?? this.query,
    mode: mode ?? this.mode,
    comic: comic ?? this.comic,
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
  );
}

class _FetchResult {
  const _FetchResult(this.page, this.totalPages, this.items);

  final int page;
  final int totalPages;
  final List<BookListItem> items;
}

class BookSearchController extends Notifier<BookSearchState> {
  Timer? _debounce;
  CancelToken? _inFlight;
  int _generation = 0;

  @override
  BookSearchState build() {
    // 筛选设置变化后重搜当前关键词。
    ref.listen<AppSettings>(appSettingsProvider, (previous, next) {
      if (previous == null) return;
      final changed =
          previous.ignoreAI != next.ignoreAI ||
          previous.ignoreJapanese != next.ignoreJapanese;
      if (changed && state.query.isNotEmpty) _run(1);
    });
    ref.onDispose(() {
      _debounce?.cancel();
      _inFlight?.cancel();
    });
    return const BookSearchState.initial();
  }

  /// 输入防抖，只提交最后一次输入并取消在途请求。
  void onInputChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed == state.query) return;
    if (trimmed.isEmpty) {
      _inFlight?.cancel();
      _generation += 1;
      state = state.copyWith(
        query: '',
        items: const <BookListItem>[],
        page: 1,
        totalPages: 1,
        loading: false,
        loadingMore: false,
        clearError: true,
      );
      return;
    }
    _debounce = Timer(searchDebounce, () => submit(trimmed));
  }

  void submit(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(query: trimmed);
    ref.read(searchHistoryProvider.notifier).add(trimmed);
    _run(1);
  }

  /// 预置搜索条件并立即搜索，供详情页标签/系列跳转使用。
  void seed({
    required String query,
    required BookSearchMode mode,
    bool? comic,
  }) {
    _debounce?.cancel();
    final trimmed = query.trim();
    state = state.copyWith(
      query: trimmed,
      mode: mode,
      comic: comic ?? state.comic,
    );
    if (trimmed.isEmpty) return;
    ref.read(searchHistoryProvider.notifier).add(trimmed);
    _run(1);
  }

  void setMode(BookSearchMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
    if (state.query.isNotEmpty) _run(1);
  }

  void setComic(bool comic) {
    if (comic == state.comic) return;
    state = state.copyWith(comic: comic);
    if (state.query.isNotEmpty) _run(1);
  }

  void retry() {
    if (state.query.isEmpty) return;
    _run(1);
  }

  void loadMore() {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    if (state.error != null) return;
    _run(state.page + 1);
  }

  Future<void> _run(int page) async {
    _inFlight?.cancel();
    final token = CancelToken();
    _inFlight = token;
    final generation = ++_generation;
    final query = state.query;
    final comic = state.comic;
    final mode = state.mode;

    // 第一页重跑时清空旧结果，否则加载期间仍显示上一次的结果。
    state = page == 1
        ? state.copyWith(
            items: const <BookListItem>[],
            page: 1,
            totalPages: 1,
            loading: true,
            loadingMore: false,
            clearError: true,
          )
        : state.copyWith(loadingMore: true, clearError: true);

    try {
      final result = await _fetch(
        keywords: query,
        mode: mode,
        comic: comic,
        startPage: page,
        token: token,
      );
      if (generation != _generation) return;
      final merged = page == 1
          ? result.items
          : mergeById(state.items, result.items, (item) => item.id);
      state = state.copyWith(
        items: merged,
        page: result.page,
        totalPages: result.totalPages,
        loading: false,
        loadingMore: false,
        clearError: true,
      );
    } on RequestCancelledError {
      // 被新一轮搜索取代，静默丢弃。
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: describeSearchError(error),
      );
    }
  }

  Future<_FetchResult> _fetch({
    required String keywords,
    required BookSearchMode mode,
    required bool comic,
    required int startPage,
    required CancelToken token,
  }) async {
    final api = ref.read(apiClientProvider);
    final settings = ref.read(appSettingsProvider);
    final collected = <BookListItem>[];
    var page = startPage;

    while (true) {
      final request = BookSearchRequest(
        keywords: keywords,
        mode: mode,
        page: page,
        size: _searchPageSize,
        ignoreJapanese: settings.ignoreJapanese,
        ignoreAI: settings.ignoreAI,
      );
      if (comic) {
        final result = await api.searchComicSeries(request, cancelToken: token);
        return _FetchResult(
          result.page,
          result.totalPages,
          result.items.map((item) => item.toBookListItem()).toList(),
        );
      }
      final result = await api.searchNovelBooks(request, cancelToken: token);
      collected.addAll(applyContentFilter(result.items, settings));
      if (result.items.isEmpty ||
          collected.length >= _searchPageSize ||
          page >= result.totalPages) {
        return _FetchResult(page, result.totalPages, collected);
      }
      page += 1;
    }
  }
}

String describeSearchError(Object error) => describeApiError(
  error,
  fallback: '无法完成搜索。',
  auth: '请重新登录后继续搜索。',
  network: '离线时无法使用搜索。',
);

final NotifierProvider<BookSearchController, BookSearchState>
bookSearchProvider = NotifierProvider<BookSearchController, BookSearchState>(
  BookSearchController.new,
);
