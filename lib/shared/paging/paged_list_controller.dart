import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import 'paged_list.dart';

/// 分页列表通用状态机：refresh 保留旧数据，retry 清空重来。
/// 每次请求带世代号，世代号过期的响应丢弃。
///
/// 子类实现取页、取主键与依赖订阅。
abstract class PagedListController<T, Arg> extends Notifier<PagedList<T>> {
  PagedListController(this.arg);

  final Arg arg;

  int _generation = 0;
  bool _disposed = false;

  /// 订阅会让整份列表失效的依赖（API、内容过滤设置等）。
  void subscribe();

  /// 拉取一页数据；实现方可在内部连续消费多个后端页。
  Future<FetchedPage<T>> fetchPage(int page);

  /// 翻页去重用的主键：数字 id 或分组键（如系列名）。
  Object idOf(T item);

  /// 离开页面后的保活时长；null 表示随页面一起丢弃。
  Duration? get keepAliveFor => null;

  /// 错误文案，子类可覆盖。
  String describeError(Object error) => describeApiError(error);

  @override
  PagedList<T> build() {
    // build 在依赖变化时重跑，onDispose 跟着触发，所以每次都重置。
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final keepAlive = keepAliveFor;
    if (keepAlive != null) {
      final link = ref.keepAlive();
      final timer = Timer(keepAlive, link.close);
      ref.onDispose(timer.cancel);
    }
    subscribe();
    unawaited(Future<void>.microtask(() => _load(preserve: false)));
    return PagedList<T>();
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
        : PagedList<T>();
    try {
      final result = await fetchPage(1);
      if (_isStale(generation)) return;
      state = PagedList<T>(
        items: result.items,
        loading: false,
        page: result.page,
        totalPages: result.totalPages,
      );
    } catch (error) {
      // 取消由更新的请求发起，状态收尾交给该请求。
      if (isCancellation(error) || _isStale(generation)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: describeError(error),
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
      state = state.copyWith(
        items: mergeById(state.items, result.items, idOf),
        loadingMore: false,
        page: result.page,
        totalPages: result.totalPages,
      );
    } catch (error) {
      if (isCancellation(error) || _isStale(generation)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeError(error),
      );
    }
  }

  /// 连续加载剩余页。批量选择里的“全选”覆盖完整结果，而不只是当前已显示页。
  Future<void> loadAll() async {
    if (state.loading || state.refreshing || state.loadingMore) return;
    while (state.hasMore && state.loadMoreError == null && !_disposed) {
      await loadMore();
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}
