// 原生阅读器的分页几何：纯数值变换，不碰 Flutter，测量层与渲染层共用一套翻页语义。

/// 行高与块高都是测量出来的浮点数，逐段累加后与视口高度往往差出零点几像素；
/// 放行 0.5 逻辑像素，免得每页最后一行被误判成溢出、被硬推到下一页。
const double _tolerance = 0.5;

/// 翻页模式的页顶偏移表；`breaks` 升序去重，元素落在 (0, contentHeight] 区间。
List<double> paginateReaderContent({
  required double contentHeight,
  required double pageHeight,
  required List<double> breaks,
}) {
  // 还没测量到尺寸时也要给渲染层一页，否则页数为 0、翻页控件无从下手。
  if (contentHeight <= 0 || pageHeight <= 0) return const <double>[0];

  final pageTops = <double>[0];
  var top = 0.0;
  while (top < contentHeight - _tolerance) {
    final limit = top + pageHeight;
    // 贪心取本页装得下的最后一个可断处；超高原子（整页插图）没有可断处时硬切一页，
    // 页顶一定推进，避免死循环。
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

/// 偏移处最靠上的可见块下标；块可能有间距，落在缝隙里取下一个块。
int readerBlockIndexAtOffset({
  required List<double> blockTops,
  required List<double> blockBottoms,
  required double offset,
}) {
  if (blockBottoms.isEmpty) return 0;
  final limit = offset + _tolerance;
  // 顶部留白与滚动回弹会给出小于首块 top 的偏移，进度必须落在首块而不是靠二分兜底。
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
