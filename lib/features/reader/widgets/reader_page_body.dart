import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../reader_pagination.dart';
import 'reader_measure_box.dart';

/// 某一页的绘制区域，高度为该页实际占用的正文高度，不含末尾空白。
Key readerPageBodyKey(int sortNum, int index) =>
    ValueKey<String>('reader-page-$sortNum-$index');

/// 翻页模式下的一页正文：只摆落在该页区间的块并裁掉溢出。
class ReaderPageBody extends StatelessWidget {
  const ReaderPageBody({
    super.key,
    required this.sortNum,
    required this.geometry,
    required this.pageTops,
    required this.blocks,
    required this.renderable,
    required this.index,
    required this.viewport,
    required this.padding,
  });

  final int sortNum;
  final ReaderGeometry? geometry;
  final List<double> pageTops;

  /// 渲染用正文块，下标与 [geometry] 的块区间对齐。
  final List<Widget> blocks;

  /// 正文块与几何是否对得上，对不上时不摆。
  final bool renderable;

  final int index;
  final Size viewport;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final geometry = this.geometry;
    if (geometry == null || !renderable || index >= pageTops.length) {
      return const SizedBox.shrink();
    }
    final top = pageTops[index];
    // 页底裁到下一页的页顶而非整屏高度，否则装不下的那一行行顶落在视口内，
    // 上半截会留在页底。
    final bottom = index + 1 < pageTops.length
        ? pageTops[index + 1]
        : math.min(top + viewport.height, geometry.height);
    final first = readerBlockIndexAtOffset(
      blockTops: geometry.blockTops,
      blockBottoms: geometry.blockBottoms,
      offset: top,
    );
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: readerPageBodyKey(sortNum, index),
          width: double.infinity,
          height: math.min(viewport.height, math.max(0, bottom - top)),
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (
                  var block = first;
                  block < blocks.length && geometry.blockTops[block] < bottom;
                  block++
                )
                  Positioned(
                    left: 0,
                    right: 0,
                    top: geometry.blockTops[block] - top,
                    child: blocks[block],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
