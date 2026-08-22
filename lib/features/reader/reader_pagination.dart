// 分页几何：纯数值变换，测量层与渲染层共用一套翻页语义。

/// 累加测量高度的浮点误差容差，单位逻辑像素。避免每页最后一行被误判成溢出。
const double _tolerance = 0.5;

/// 翻页模式的页顶偏移表；`breaks` 升序去重，元素落在 (0, contentHeight] 区间。
List<double> paginateReaderContent({
  required double contentHeight,
  required double pageHeight,
  required List<double> breaks,
}) {
  // 未测量到尺寸时也返回一页，否则页数为 0。
  if (contentHeight <= 0 || pageHeight <= 0) return const <double>[0];

  final pageTops = <double>[0];
  var top = 0.0;
  while (top < contentHeight - _tolerance) {
    final limit = top + pageHeight;
    // 取本页装得下的最后一个断点；无断点时按页高硬切，保证页顶推进。
    final next = _lastBreakWithin(breaks, top, limit + _tolerance) ?? limit;
    if (next >= contentHeight - _tolerance) break;
    pageTops.add(next);
    top = next;
  }
  return pageTops;
}

/// `breaks` 升序，取 (lower, upper] 内最大的断点。
double? _lastBreakWithin(List<double> breaks, double lower, double upper) {
  var low = 0;
  var high = breaks.length - 1;
  var found = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (breaks[mid] <= upper) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  if (found < 0) return null;
  final value = breaks[found];
  return value > lower ? value : null;
}

/// 给定纵向偏移落在第几页（越界收敛到首/末页）。
int readerPageIndexForOffset(List<double> pageTops, double offset) {
  if (pageTops.isEmpty) return 0;
  final limit = offset + _tolerance;
  var low = 0;
  var high = pageTops.length - 1;
  var index = 0;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (pageTops[mid] <= limit) {
      index = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return index;
}

/// 偏移处最靠上的可见块下标；偏移落在块间距内时取下一个块。
int readerBlockIndexAtOffset({
  required List<double> blockTops,
  required List<double> blockBottoms,
  required double offset,
}) {
  if (blockBottoms.isEmpty) return 0;
  final limit = offset + _tolerance;
  // 顶部留白与滚动回弹会给出小于首块 top 的偏移，此时取首块。
  if (blockTops.isNotEmpty && limit < blockTops.first) return 0;

  var low = 0;
  var high = blockBottoms.length - 1;
  var index = high;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (blockBottoms[mid] > limit) {
      index = mid;
      high = mid - 1;
    } else {
      low = mid + 1;
    }
  }
  return index;
}

/// 进度落在哪个块上。
///
/// 翻页模式下页顶的块常常跨自上一页，进度要记在本页第一个整块上，
/// 否则按 locator 重开会退回上一页，上报的位置也不幂等。
int readerLocatorBlockIndex({
  required List<double> blockTops,
  required List<double> blockBottoms,
  required double offset,
  required bool paged,
  required double pageHeight,
}) {
  final index = readerBlockIndexAtOffset(
    blockTops: blockTops,
    blockBottoms: blockBottoms,
    offset: offset + 1,
  );
  if (!paged) return index;
  var candidate = index;
  while (candidate < blockTops.length && blockTops[candidate] < offset - 0.5) {
    candidate++;
  }
  // 没有整块能放进本页（跨多页的长段、整页插图）时，仍以跨页的那个块为准。
  return candidate < blockTops.length &&
          blockTops[candidate] < offset + pageHeight
      ? candidate
      : index;
}

/// 跨章翻页条：把相邻章的页首尾相接，摊平成一个全局页序。
///
/// 只做下标换算，[T] 是调用方的章节表示，页数由 `pageCount` 取。
class ReaderPageStrip<T> {
  const ReaderPageStrip._(
    this.chapters,
    this._starts,
    this._counts,
    this.pages,
  );

  const ReaderPageStrip.empty()
    : chapters = const <Never>[],
      _starts = const <int>[],
      _counts = const <int>[],
      pages = 0;

  factory ReaderPageStrip.of(
    List<T> chapters,
    int Function(T chapter) pageCount,
  ) {
    final starts = <int>[];
    final counts = <int>[];
    var total = 0;
    for (final chapter in chapters) {
      final count = pageCount(chapter);
      starts.add(total);
      counts.add(count);
      total += count;
    }
    return ReaderPageStrip<T>._(chapters, starts, counts, total);
  }

  final List<T> chapters;
  final List<int> _starts;
  final List<int> _counts;

  /// 条上的总页数，也就是 `PageView` 的 itemCount。
  final int pages;

  bool get isEmpty => chapters.isEmpty;

  /// [chapter] 的第 [page] 页在条上的下标；不在条上时退回 [page] 本身。
  int globalPageOf(T chapter, int page) {
    final index = chapters.indexOf(chapter);
    return index < 0 ? page : _starts[index] + page;
  }

  /// 条上第 [page] 页属于哪一章的第几页；越界返回 null。
  (T, int)? locate(int page) {
    for (var index = chapters.length - 1; index >= 0; index--) {
      if (page < _starts[index]) continue;
      final local = page - _starts[index];
      return local < _counts[index] ? (chapters[index], local) : null;
    }
    return null;
  }
}
