import 'dart:math' as math;

import '../../data/api/models.dart';

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

/// 当前页两侧优先，再沿阅读方向多取 4 页。
List<int> createComicPrefetchPlan(int current, int total, int direction) {
  final plan = <int>[];
  void add(int index) {
    if (index < 0 || index >= total || plan.contains(index)) return;
    plan.add(index);
  }

  add(current);
  add(current + 1);
  add(current - 1);
  for (var offset = 0; offset < 4; offset++) {
    add(current + direction * (offset + 2));
  }
  return plan;
}

/// 宽屏/矮屏下限制连续模式正文宽度，免得单页被拉太宽。
double getContinuousComicContentWidth(double width, double height) =>
    height > 0 && width / height > 0.7 ? math.min(width, height * 0.7) : width;
