import 'package:flutter/material.dart';

import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/grid_tile_parts.dart';

/// 快照里缺失详情的书籍占位卡片，仅支持被选中后移出书架。
class UnavailableBookTile extends StatelessWidget {
  const UnavailableBookTile({
    super.key,
    required this.selected,
    required this.sorting,
    required this.onTap,
    required this.onLongPress,
  });

  final bool selected;
  final bool sorting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: BookGridLayout.coverAspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant, width: 0.5),
              ),
              // DecoratedBox 只画描边不裁剪，蒙层需自行裁到同样的圆角。
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(
                      child: Icon(
                        Icons.menu_book_outlined,
                        size: 32,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    GridSelectionOverlay(selected: selected, sorting: sorting),
                  ],
                ),
              ),
            ),
          ),
          GridTileTitle(title: '书籍不可用', color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
