import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_image.dart';
import '../../../shared/widgets/image_preview.dart';

const double bookHeroHeight = 280;

/// 详情页封面的显示高度。模糊底图、主封面、取色三处共用它，好让三者算出同一个
/// 尺寸档、同一个缓存键 —— 整页只下载并解码一张封面。
///
/// 主封面外层容器固定 100×150，是三者里唯一对清晰度有要求的，所以按它定档。
/// 改这里之前先确认三处仍然共用，否则会静默退化成多次下载。
const double bookCoverDisplayHeight = 150;

class BookHero extends StatelessWidget {
  const BookHero({super.key, required this.detail});

  final BookDetail detail;

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
              // 28px 高斯模糊后细节全失，本可以只要最小档；但主封面那张整页反正
              // 都要下，跟它同档就能直接复用，多下一张最小档反而更亏。
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
                    Text(
                      detail.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(
                        fontSize: 22,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
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
