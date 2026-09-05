import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_cover_grid_item.dart';

/// 打开书籍详情。
void openBookDetail(BuildContext context, BookListItem book) {
  context.push('/book/${book.id}');
}

/// 首页分区的静态网格，不滚动，按父级宽度分列。
class BookGridPreview extends StatelessWidget {
  const BookGridPreview({
    super.key,
    required this.books,
    required this.onOpen,
    this.showRank = false,
    this.maxRows = 2,
  });

  final List<BookListItem> books;
  final void Function(BookListItem book) onOpen;
  final bool showRank;
  final int maxRows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // 内边距已由父级扣除。
      final layout = BookGridLayout.of(
        constraints.maxWidth,
        horizontalPadding: 0,
      );
      final limit = layout.columns * maxRows;
      return _gridRows(
        layout: layout,
        itemCount: books.length < limit ? books.length : limit,
        // 一张封面淡入只重绘自己那格，手写的 Column/Row 没有天然的绘制边界。
        itemBuilder: (index) => RepaintBoundary(
          child: BookCoverGridItem.fromBook(
            books[index],
            coverHeight: layout.coverHeight,
            rank: showRank ? index + 1 : null,
            onTap: () => onOpen(books[index]),
          ),
        ),
      );
    },
  );
}

/// 首页分区的网格骨架：固定行数。
class BookGridPreviewSkeleton extends StatelessWidget {
  const BookGridPreviewSkeleton({super.key, this.rows = 2});

  final int rows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = BookGridLayout.of(
        constraints.maxWidth,
        horizontalPadding: 0,
      );
      return _gridRows(
        layout: layout,
        itemCount: layout.columns * rows,
        itemBuilder: (_) => const BookGridSkeletonTile(),
      );
    },
  );
}

/// 手动按行摆放，使不满一行的卡片左对齐且宽度与整行一致。
Widget _gridRows({
  required BookGridLayout layout,
  required int itemCount,
  required Widget Function(int index) itemBuilder,
}) {
  final rows = <Widget>[];
  for (var start = 0; start < itemCount; start += layout.columns) {
    final cells = <Widget>[];
    for (var column = 0; column < layout.columns; column++) {
      if (column > 0) {
        cells.add(const SizedBox(width: BookGridLayout.columnGap));
      }
      final index = start + column;
      cells.add(
        SizedBox(
          width: layout.tileWidth,
          child: index < itemCount ? itemBuilder(index) : null,
        ),
      );
    }
    if (rows.isNotEmpty) {
      rows.add(const SizedBox(height: BookGridLayout.rowGap));
    }
    rows.add(
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: rows,
  );
}
