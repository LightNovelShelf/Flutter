import 'package:flutter/material.dart';

import '../../data/api/models.dart';
import '../book_badges.dart';
import '../layout/book_grid_layout.dart';
import 'book_image.dart';
import 'grid_tile_parts.dart';

const List<Color> _rankBadgeColors = <Color>[
  Color(0xFFFFD700),
  Color(0xFF78909C),
  Color(0xFFCD7F32),
];

/// 通用书籍网格卡片：2:3 封面 + 徽章层 + 固定 40 高的两行标题。
class BookCoverGridItem extends StatelessWidget {
  const BookCoverGridItem({
    super.key,
    required this.title,
    required this.coverUrl,
    required this.coverHeight,
    this.coverPlaceholder,
    this.category,
    this.level,
    this.interiorLevel,
    this.rank,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.sorting = false,
    this.overlayLabel,
  });

  BookCoverGridItem.fromBook(
    BookListItem book, {
    super.key,
    required this.coverHeight,
    this.rank,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.sorting = false,
    this.overlayLabel,
  }) : title = book.title,
       coverUrl = book.coverUrl,
       coverPlaceholder = book.coverPlaceholder,
       category = book.category,
       level = book.level,
       interiorLevel = book.interiorLevel;

  final String title;
  final String coverUrl;
  final String? coverPlaceholder;
  final BookCategory? category;
  final int? level;
  final int? interiorLevel;

  /// 封面在网格里的高度（逻辑像素），一般是 `layout.tileWidth * 1.5`。
  final double coverHeight;
  final int? rank;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool sorting;
  final String? overlayLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final categoryBadge = resolveCategoryBadge(category);
    final levelBadge = resolveLevelBadge(
      level: level,
      interiorLevel: interiorLevel,
    );
    final rankValue = rank;

    return InkWell(
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
                    BookImage(
                      url: coverUrl,
                      displayHeight: coverHeight,
                      blurHash: coverPlaceholder,
                      // 封面在滚动中缩放，需要更稳定的亚像素重采样。
                      filterQuality: FilterQuality.high,
                    ),
                    if (levelBadge != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: LevelBadge(spec: levelBadge),
                      ),
                    if (categoryBadge != null)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CategoryBadge(definition: categoryBadge),
                      ),
                    if (rankValue != null && rankValue >= 1 && rankValue <= 3)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _rankBadgeColors[rankValue - 1],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$rankValue',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    GridSelectionOverlay(selected: selected, sorting: sorting),
                    if (overlayLabel != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ColoredBox(
                          color: const Color(0x99000000),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              overlayLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          GridTileTitle(title: title),
        ],
      ),
    );
  }
}

class BookGridSkeletonTile extends StatelessWidget {
  const BookGridSkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 13,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        AspectRatio(
          aspectRatio: BookGridLayout.coverAspectRatio,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 7),
        bar(0.88),
        const SizedBox(height: 4),
        bar(0.58),
      ],
    );
  }
}
