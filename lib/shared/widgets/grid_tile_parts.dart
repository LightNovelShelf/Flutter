import 'package:flutter/material.dart';

import '../layout/book_grid_layout.dart';

/// 网格卡片的公共零件：书籍、文件夹、占位卡片共用的选中/排序蒙层与标题框。

/// 覆盖在封面上的多选与排序蒙层；选中优先于排序。
class GridSelectionOverlay extends StatelessWidget {
  const GridSelectionOverlay({
    super.key,
    required this.selected,
    required this.sorting,
  });

  final bool selected;
  final bool sorting;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return const ColoredBox(
        color: Color(0xB8D9475D),
        child: Center(child: Icon(Icons.check, size: 34, color: Colors.white)),
      );
    }
    if (sorting) {
      return const ColoredBox(
        color: Color(0x7A000000),
        child: Center(
          child: Icon(Icons.drag_indicator, size: 36, color: Colors.white),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 固定高度的两行标题框，网格里每张卡片的总高度必须一致。
class GridTileTitle extends StatelessWidget {
  const GridTileTitle({super.key, required this.title, this.color});

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BookGridLayout.titleBoxHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 16 / 13,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    ),
  );
}
