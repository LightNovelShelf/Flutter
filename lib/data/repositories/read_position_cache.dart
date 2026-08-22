import '../api/models.dart';

/// 进程内阅读进度缓存，阅读器写入后详情页与书架可直接读到最新章节。
class ReadPositionCache {
  ReadPositionCache._();

  static final Map<int, BookReadPosition> _positions =
      <int, BookReadPosition>{};

  static BookReadPosition? read(int bookId) => _positions[bookId];

  static void stage(int bookId, BookReadPosition position) {
    _positions[bookId] = position;
  }

  static void clear() => _positions.clear();

  /// 与服务端返回的进度合并，取 `readAt` 更晚的一份；时间相同或缺失时以缓存为准。
  static BookReadPosition? merge(int bookId, BookReadPosition? remote) {
    final cached = _positions[bookId];
    if (cached == null) return remote;
    if (remote == null) return cached;
    final cachedAt = cached.readAt;
    final remoteAt = remote.readAt;
    if (cachedAt == null && remoteAt != null) return remote;
    if (cachedAt == null || remoteAt == null) return cached;
    return remoteAt.isAfter(cachedAt) ? remote : cached;
  }
}
