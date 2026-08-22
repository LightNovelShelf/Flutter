import 'package:flutter/material.dart';

import '../layout/book_grid_layout.dart';
import 'book_cover_grid_item.dart';

/// 骨架网格 sliver，首屏与翻页补行共用。
Widget bookGridSkeletonSliver({
  required BookGridLayout layout,
  required int count,
  required EdgeInsets padding,
  double? mainAxisSpacing,
}) => SliverPadding(
  padding: padding,
  sliver: SliverGrid(
    gridDelegate: layout.skeletonGridDelegate(mainAxisSpacing: mainAxisSpacing),
    delegate: SliverChildBuilderDelegate(
      (_, _) => const BookGridSkeletonTile(),
      childCount: count,
      addAutomaticKeepAlives: false,
    ),
  ),
);
