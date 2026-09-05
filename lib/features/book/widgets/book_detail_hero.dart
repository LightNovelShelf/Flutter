import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_image.dart';
import '../../../shared/widgets/image_preview.dart';

const double bookHeroHeight = 280;

/// 详情页封面显示高度，单位逻辑像素。模糊底图、主封面、取色三处共用，得到同一
/// 尺寸档与同一缓存键，整页只下载解码一张封面。
///
/// 档位按主封面的 100×150 容器定，改动前确认三处仍共用，否则会退化成多次下载。
const double bookCoverDisplayHeight = 150;

class BookHero extends StatelessWidget {
  const BookHero({super.key, required this.detail});

  final BookDetail detail;

  Widget _title(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      detail.title,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 22,
        height: 1.28,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final category = detail.category;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: colors.surface),
        if (detail.coverUrl.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Opacity(
              opacity: 0.65,
              // 与主封面同档以复用同一张图，模糊底图本身不需要这个清晰度。
              child: BookImage(
                url: detail.coverUrl,
                displayHeight: bookCoverDisplayHeight,
                blurHash: detail.coverPlaceholder,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors.surface.withValues(alpha: 0.1),
                colors.surface.withValues(alpha: 0.55),
                colors.surface,
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                width: bookCoverDisplayHeight * BookGridLayout.coverAspectRatio,
                height: bookCoverDisplayHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: colors.surfaceContainerHighest,
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x2D000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: detail.coverUrl.isEmpty
                    ? Icon(
                        Icons.menu_book_outlined,
                        size: 40,
                        color: colors.onSurfaceVariant,
                      )
                    : Builder(
                        // 唯一预览原图的地方：封面显示尺寸小，放大看要清晰度。
                        builder: (context) => GestureDetector(
                          onTap: () => unawaited(
                            showImagePreview(
                              context,
                              url: detail.coverUrl,
                              sourceRect: globalRectOf(context),
                            ),
                          ),
                          child: BookImage(
                            url: detail.coverUrl,
                            displayHeight: bookCoverDisplayHeight,
                            blurHash: detail.coverPlaceholder,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _title(context),
                    if (detail.authorName != null &&
                        detail.authorName!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        detail.authorName!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (category != null && category.shortName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.shortName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
