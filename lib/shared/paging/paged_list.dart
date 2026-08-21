/// 一次「可见页」拉取的结果：`page` 是实际消费到的后端页码，
/// 本地过滤可能连着吃掉好几页才凑够一屏。
class FetchedPage<T> {
  const FetchedPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<T> items;
  final int page;
  final int totalPages;
}

/// 分页列表状态：`loading` 是首屏、`refreshing` 是保留旧数据的下拉刷新、
/// `loadingMore` 是翻页；两类错误分开，翻页失败不该清空已有内容。
class PagedList<T> {
  const PagedList({
    this.items = const [],
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.page = 0,
    this.totalPages = 1,
  });

  final List<T> items;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;
  final int page;
  final int totalPages;

  /// `page == 0` 表示首屏还没落地，此时不允许翻页。
  bool get hasMore => page > 0 && page < totalPages;

  PagedList<T> copyWith({
    List<T>? items,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    int? page,
    int? totalPages,
  }) => PagedList<T>(
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

/// 分页合并：保留既有顺序，只追加没见过的 id。服务端会按热度重排，翻页必然撞重复。
/// `incoming` 为空时原样返回同一个实例，避免下游无谓重建。
List<T> mergeById<T>(
  List<T> existing,
  List<T> incoming,
  int Function(T item) idOf,
) {
  if (incoming.isEmpty) return existing;
  final seen = <int>{for (final item in existing) idOf(item)};
  final merged = List<T>.of(existing);
  for (final item in incoming) {
    if (seen.add(idOf(item))) merged.add(item);
  }
  return merged;
}
