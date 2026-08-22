import 'dart:math' as math;

import 'package:flutter/rendering.dart';

class BookGridLayout {
  const BookGridLayout({
    required this.columns,
    required this.tileWidth,
    required this.contentWidth,
  });

  static const double columnGap = 10;
  static const double rowGap = 12;
  static const double horizontalPadding = 20;
  static const double coverAspectRatio = 2 / 3;
  static const double titleBoxHeight = 40;

  final int columns;
  final double tileWidth;
  final double contentWidth;

  static int columnsFor(double contentWidth) {
    if (contentWidth >= 1280) return 8;
    if (contentWidth >= 1024) return 7;
    if (contentWidth >= 768) return 6;
    if (contentWidth >= 600) return 5;
    if (contentWidth >= 480) return 4;
    return 3;
  }

  factory BookGridLayout.of(
    double windowWidth, {
    double horizontalPadding = BookGridLayout.horizontalPadding,
  }) {
    final contentWidth = math.max(1.0, windowWidth - 2 * horizontalPadding);
    final columns = columnsFor(contentWidth);
    final tileWidth = ((contentWidth - (columns - 1) * columnGap) / columns)
        .floorToDouble();
    return BookGridLayout(
      columns: columns,
      tileWidth: tileWidth,
      contentWidth: contentWidth,
    );
  }

  /// 封面区高度（不含标题区），也是向图床请求尺寸档的依据。
  double get coverHeight => tileWidth / coverAspectRatio;

  double get tileHeight => coverHeight + titleBoxHeight;

  /// 骨架屏单块高度：封面 + 7 间距 + 两条 13 高的文本占位 + 4 间距。
  double get skeletonTileHeight => coverHeight + 7 + 13 + 4 + 13;

  int skeletonCount(double windowHeight, {double headerOffset = 110}) {
    final rows = math.max(
      1,
      ((windowHeight - headerOffset) / (skeletonTileHeight + rowGap)).ceil(),
    );
    return rows * columns;
  }

  /// 加载更多时补齐残行并额外追加一整行骨架。
  int loadMorePlaceholderCount(int itemCount) =>
      ((columns - itemCount % columns) % columns) + columns;

  double get childAspectRatio => tileWidth / tileHeight;

  /// 卡片网格：`childAspectRatio` 按卡片实际高度。
  SliverGridDelegate tileGridDelegate({double? mainAxisSpacing}) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: BookGridLayout.columnGap,
        mainAxisSpacing: mainAxisSpacing ?? BookGridLayout.rowGap,
        childAspectRatio: childAspectRatio,
      );

  /// 骨架网格：骨架卡片比真实卡片矮，用 `skeletonTileHeight`。
  SliverGridDelegate skeletonGridDelegate({double? mainAxisSpacing}) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: BookGridLayout.columnGap,
        mainAxisSpacing: mainAxisSpacing ?? BookGridLayout.rowGap,
        childAspectRatio: tileWidth / skeletonTileHeight,
      );
}
