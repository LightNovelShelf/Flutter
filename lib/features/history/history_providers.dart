import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';

/// 服务端批量接口单次最多 24 个 ID，分页粒度必须与之对齐。
const int historyPageSize = 24;

enum HistoryTab { novel, comic }

String describeHistoryError(Object error, {String fallback = '阅读历史暂时不可用。'}) =>
    describeApiError(
      error,
      fallback: fallback,
      auth: '登录状态已过期，请重新登录后继续。',
      network: '网络连接不可用，请检查后重试。',
      normalize: true,
    );

/// 单个分页（小说或漫画）的状态：完整 ID 序列 + 已翻页的书籍。
@immutable
class HistoryTabState {
  const HistoryTabState({
    this.ids = const <int>[],
    this.items = const <BookListItem>[],
    this.loadedPages = 0,
    this.loadingMore = false,
    this.error,
  });

  final List<int> ids;
  final List<BookListItem> items;
  final int loadedPages;
  final bool loadingMore;
  final String? error;

  int get totalPages => (ids.length / historyPageSize).ceil();

  bool get hasMore => loadedPages < totalPages;

  /// 首页尚未加载且无错误，此时展示骨架屏。
  bool get isInitialLoading => loadedPages == 0 && ids.isNotEmpty && error == null;

  HistoryTabState copyWith({
    List<int>? ids,
    List<BookListItem>? items,
    int? loadedPages,
    bool? loadingMore,
    String? error,
    bool clearError = false,
  }) =>
      HistoryTabState(
        ids: ids ?? this.ids,
        items: items ?? this.items,
        loadedPages: loadedPages ?? this.loadedPages,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

@immutable
class HistoryState {
  const HistoryState({
    required this.novel,
    required this.comic,
    this.clearing = false,
  });

  static const HistoryState empty = HistoryState(
    novel: HistoryTabState(),
    comic: HistoryTabState(),
  );

  final HistoryTabState novel;
  final HistoryTabState comic;
  final bool clearing;

  HistoryTabState tab(HistoryTab tab) =>
      tab == HistoryTab.novel ? novel : comic;

  bool get isEmpty => novel.ids.isEmpty && comic.ids.isEmpty;

  HistoryState copyWith({
    HistoryTabState? novel,
    HistoryTabState? comic,
    bool? clearing,
  }) =>
      HistoryState(
        novel: novel ?? this.novel,
        comic: comic ?? this.comic,
        clearing: clearing ?? this.clearing,
      );

  HistoryState withTab(HistoryTab which, HistoryTabState next) =>
      which == HistoryTab.novel ? copyWith(novel: next) : copyWith(comic: next);
}

/// 阅读历史：先取全量 ID 索引，再按 24 个一页补齐书籍详情。
class HistoryController extends AsyncNotifier<HistoryState> {
  ApiClient get _api => ref.read(apiClientProvider);

  /// 代际号：索引重载或清空后丢弃在途的翻页响应。
  int _generation = 0;

  @override
  Future<HistoryState> build() async {
    if (!ref.watch(authSnapshotProvider).isAuthenticated) return HistoryState.empty;
    final generation = ++_generation;
    final history = await _api.getReadHistory();
    final indexed = HistoryState(
      novel: HistoryTabState(ids: history.novelIds),
      comic: HistoryTabState(ids: history.comicIds),
    );
    // 两个分页的第一页同时预取，切换分段控件时无需等待。
    final pages = await Future.wait<HistoryTabState>(<Future<HistoryTabState>>[
      _guardedPage(indexed.novel, HistoryTab.novel),
      _guardedPage(indexed.comic, HistoryTab.comic),
    ]);
    if (generation != _generation) return state.value ?? indexed;
    return HistoryState(novel: pages[0], comic: pages[1]);
  }

  Future<HistoryTabState> _guardedPage(HistoryTabState tab, HistoryTab which) async {
    try {
      return await _fetchPage(tab, which);
    } catch (error) {
      return tab.copyWith(error: describeHistoryError(error));
    }
  }

  /// 追加 `tab.loadedPages + 1` 页；服务端返回顺序不保证，按请求顺序还原。
  Future<HistoryTabState> _fetchPage(HistoryTabState tab, HistoryTab which) async {
    final start = tab.loadedPages * historyPageSize;
    if (start >= tab.ids.length) return tab;
    final slice = tab.ids.sublist(
      start,
      math.min(start + historyPageSize, tab.ids.length),
    );
    final fetched = which == HistoryTab.novel
        ? await _api.getBookListByIds(slice)
        : (await _api.getComicSeriesByIds(slice))
            .items
            .map((series) => series.toBookListItem())
            .toList();
    return tab.copyWith(
      items: _orderBySlice(
        tab.items,
        fetched,
        slice,
        dedupeByTitle: which == HistoryTab.comic,
      ),
      loadedPages: tab.loadedPages + 1,
      loadingMore: false,
      clearError: true,
    );
  }

  /// 按请求的 id 顺序合并，服务端未返回的 id 丢弃（书可能已下架）。
  static List<BookListItem> _orderBySlice(
    List<BookListItem> existing,
    List<BookListItem> fetched,
    List<int> slice, {
    required bool dedupeByTitle,
  }) {
    final byId = <int, BookListItem>{for (final book in fetched) book.id: book};
    final seenIds = <int>{for (final book in existing) book.id};
    // 漫画按系列聚合，同一系列可能在后续页里再次出现，额外按标题去重。
    final seenTitles = <String>{
      if (dedupeByTitle) for (final book in existing) book.title,
    };
    final merged = List<BookListItem>.of(existing);
    for (final id in slice) {
      final book = byId[id];
      if (book == null) continue;
      if (!seenIds.add(book.id)) continue;
      if (dedupeByTitle && !seenTitles.add(book.title)) continue;
      merged.add(book);
    }
    return merged;
  }

  Future<void> _appendPage(HistoryTab which) async {
    final current = state.value;
    if (current == null || current.clearing) return;
    final tab = current.tab(which);
    if (tab.loadingMore || !tab.hasMore) return;
    final generation = _generation;
    state = AsyncValue<HistoryState>.data(
      current.withTab(which, tab.copyWith(loadingMore: true, clearError: true)),
    );
    try {
      final next = await _fetchPage(state.value!.tab(which), which);
      if (generation != _generation) return;
      state = AsyncValue<HistoryState>.data(state.value!.withTab(which, next));
    } catch (error) {
      if (generation != _generation) return;
      state = AsyncValue<HistoryState>.data(
        state.value!.withTab(
          which,
          state.value!.tab(which).copyWith(
                loadingMore: false,
                error: describeHistoryError(error),
              ),
        ),
      );
    }
  }

  /// 触底加载，出错后不再自动重试。
  Future<void> loadMore(HistoryTab which) async {
    if (state.value?.tab(which).error != null) return;
    await _appendPage(which);
  }

  Future<void> retry(HistoryTab which) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue<HistoryState>.data(
      current.withTab(which, current.tab(which).copyWith(clearError: true)),
    );
    await _appendPage(which);
  }

  /// 下拉刷新，重拉索引；清空过程中直接返回。
  Future<void> reload() async {
    if (state.value?.clearing ?? false) return;
    _generation += 1;
    ref.invalidateSelf();
    await future;
  }

  /// 清空阅读历史，失败时抛出。
  Future<void> clear() async {
    final current = state.value;
    if (current == null || current.clearing) return;
    state = AsyncValue<HistoryState>.data(current.copyWith(clearing: true));
    try {
      await _api.clearReadHistory();
      _generation += 1;
      state = const AsyncValue<HistoryState>.data(HistoryState.empty);
    } catch (error) {
      state = AsyncValue<HistoryState>.data(current.copyWith(clearing: false));
      rethrow;
    }
  }
}

final AsyncNotifierProvider<HistoryController, HistoryState> historyProvider =
    AsyncNotifierProvider<HistoryController, HistoryState>(HistoryController.new);
