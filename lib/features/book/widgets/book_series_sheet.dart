import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/models.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/book_image.dart';

void showBookSeriesSheet(
  BuildContext context,
  BookDetail detail,
  int currentBookId,
) {
  showDraggableSheet<void>(
    context,
    initialSize: 0.65,
    minSize: 0.4,
    showDragHandle: true,
    builder: (sheetContext, controller) => ListView.separated(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        24 + MediaQuery.paddingOf(sheetContext).bottom,
      ),
      itemCount: detail.series.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SheetHeader(
                  icon: Icons.library_books_outlined,
                  title: '系列',
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                Text(
                  '${detail.seriesTitle} · ${detail.series.length} 本',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        final book = detail.series[index - 1];
        final current = book.id == currentBookId;
        return _SeriesBookRow(
          book: book,
          current: current,
          onTap: () {
            Navigator.of(sheetContext).pop();
            if (!current) context.push('/book/${book.id}');
          },
        );
      },
    ),
  );
}

class _SeriesBookRow extends StatelessWidget {
  const _SeriesBookRow({
    required this.book,
    required this.current,
    required this.onTap,
  });

  final BookSeriesItem book;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: current ? colors.primaryContainer : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 56,
                height: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: book.coverUrl.isEmpty
                      ? ColoredBox(
                          color: colors.surfaceContainer,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : BookImage(
                          url: book.coverUrl,
                          displayHeight: 84,
                          blurHash: book.coverPlaceholder,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 84,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: current
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                        ),
                      ),
                      if (current) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          '当前书籍',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onPrimaryContainer),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
