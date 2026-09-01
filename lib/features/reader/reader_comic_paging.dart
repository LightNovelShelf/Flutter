import 'dart:math' as math;

import '../../data/api/models.dart';

const int comicPrefetchCount = 4;

/// 漫画整页的取图与排布：纯数据变换，翻页/连续两种模式共用。

class ComicPageSlot {
  const ComicPageSlot({required this.index, required this.image});

  final int index;
  final ComicImage? image;
}

List<ComicPageSlot> createComicPageSlots(int total) => <ComicPageSlot>[
  for (var index = 0; index < math.max(0, total); index++)
    ComicPageSlot(index: index, image: null),
];

List<ComicPageSlot> mergeComicPageBatch(
  List<ComicPageSlot> slots,
  int skip,
  List<ComicImage> images,
) {
  final next = List<ComicPageSlot>.of(slots);
  for (var offset = 0; offset < images.length; offset++) {
    final index = skip + offset;
    if (index < 0 || index >= next.length) continue;
    next[index] = ComicPageSlot(index: index, image: images[offset]);
  }
  return next;
}

int getComicPageBatchStart(int index, int total, int batchSize) {
  final clamped = total <= 0 ? 0 : index.clamp(0, total - 1);
  return (clamped ~/ batchSize) * batchSize;
}

/// 只预取当前页之后的 4 页。
List<int> createComicPrefetchPlan(int current, int total) {
  final plan = <int>[];
  for (var offset = 1; offset <= comicPrefetchCount; offset++) {
    final index = current + offset;
    if (index >= total) break;
    if (index >= 0) plan.add(index);
  }
  return plan;
}

/// 双页模式的分屏：竖版页两两成对，横跨两页的宽图（[aspects] < 1）独占一屏。
///
/// [offsetFirstPage] 开启时，第一页作为封面独占一屏，其余页面再从第二页开始配对。
/// [aspects] 是每页的高宽比，尚未取到图的页按竖版算，取到真实比例后重排一次。
/// 宽图会把后面的配对整体错开一位，这正是原书的跨页关系。
List<List<int>> createComicSpreads(
  List<double> aspects, {
  bool offsetFirstPage = false,
}) {
  final spreads = <List<int>>[];
  var index = 0;
  if (offsetFirstPage && aspects.isNotEmpty) {
    spreads.add(<int>[0]);
    index = 1;
  }
  while (index < aspects.length) {
    final pairable = aspects[index] >= 1 && index + 1 < aspects.length;
    if (pairable && aspects[index + 1] >= 1) {
      spreads.add(<int>[index, index + 1]);
      index += 2;
      continue;
    }
    spreads.add(<int>[index]);
    index++;
  }
  return spreads;
}

/// 每页落在第几屏，供页码与分屏下标互查。
List<int> createComicSpreadIndex(List<List<int>> spreads, int pageCount) {
  final index = List<int>.filled(math.max(0, pageCount), 0);
  for (var spread = 0; spread < spreads.length; spread++) {
    for (final page in spreads[spread]) {
      if (page >= 0 && page < index.length) index[page] = spread;
    }
  }
  return index;
}

/// 宽屏或矮屏下限制连续模式的正文宽度，避免单页过宽。
double getContinuousComicContentWidth(double width, double height) =>
    height > 0 && width / height > 0.7 ? math.min(width, height * 0.7) : width;
