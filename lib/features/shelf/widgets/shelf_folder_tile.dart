import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_image.dart';

/// 书架文件夹卡片：与书籍卡片同尺寸，内含书籍按 2×2 排列。
class ShelfFolderTile extends StatelessWidget {
  const ShelfFolderTile({
    super.key,
    required this.title,
    required this.covers,
    required this.childCount,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.sorting = false,
  });

  final String title;

  /// 直接子书籍的封面，最多取前 4 本。
  final List<BookListItem> covers;

  /// 该文件夹下的直接条目数，用于无障碍朗读。
  final int childCount;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool sorting;

  Widget _preview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (covers.isEmpty) {
      return Center(
        child: Icon(
          Icons.folder_open_outlined,
          size: 56,
          color: colors.primary,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2×2 预览：左右各 10 内边距、中间 8 间距，剩余宽度对半分。
        final slotWidth = math.max(1.0, (constraints.maxWidth - 28) / 2);
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            runAlignment: WrapAlignment.start,
            children: <Widget>[
              for (final book in covers.take(4))
                SizedBox(
                  width: slotWidth,
                  height: (slotWidth * 1.5).roundToDouble(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: colors.surfaceContainerHigh,
                      child: BookImage(
                        url: book.coverUrl,
                        blurHash: book.coverPlaceholder,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '文件夹 $title，共 $childCount 项',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            AspectRatio(
              aspectRatio: BookGridLayout.coverAspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: colors.surfaceContainer,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _preview(context),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: const EdgeInsets.all(4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.folder,
                            size: 15,
                            color: colors.onPrimary,
                          ),
                        ),
                      ),
                      if (selected)
                        const ColoredBox(
                          color: Color(0xB8D9475D),
                          child: Center(
                            child: Icon(
                              Icons.check,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (sorting && !selected)
                        const ColoredBox(
                          color: Color(0x7A000000),
                          child: Center(
                            child: Icon(
                              Icons.drag_indicator,
                              size: 36,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
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
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
