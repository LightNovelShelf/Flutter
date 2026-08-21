import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_image.dart';
import '../../../shared/widgets/grid_tile_parts.dart';

/// 小说系列卡片，尺寸同书卡，封面取系列内最新一本，角标为系列册数。
class NovelSeriesTile extends StatelessWidget {
  const NovelSeriesTile({
    super.key,
    required this.series,
    required this.coverHeight,
    this.onTap,
  });

  final NovelSeriesListItem series;

  /// 封面区高度，用于图床按尺寸档取图。
  final double coverHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '系列 ${series.name}，共 ${series.bookCount} 本',
      child: InkWell(
        onTap: onTap,
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
                      if (series.coverUrl.isEmpty)
                        Center(
                          child: Icon(
                            Icons.folder_open_outlined,
                            size: 48,
                            color: colors.primary,
                          ),
                        )
                      else
                        BookImage(
                          url: series.coverUrl,
                          displayHeight: coverHeight,
                          blurHash: series.coverPlaceholder,
                          filterQuality: FilterQuality.high,
                        ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.folder,
                                size: 13,
                                color: colors.onPrimary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${series.bookCount}',
                                style: TextStyle(
                                  color: colors.onPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GridTileTitle(title: series.name),
          ],
        ),
      ),
    );
  }
}
