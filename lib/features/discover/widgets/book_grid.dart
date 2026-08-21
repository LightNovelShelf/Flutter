import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_cover_grid_item.dart';
import '../../../shared/widgets/paged_grid.dart';

/// 打开书籍详情，漫画需带上系列名，详情页据此拉取系列信息。
///
/// [fromSeries] 为来源系列页的名称，详情页返回系列时据此出栈而不是重复压栈。
void openBookDetail(
  BuildContext context,
  BookListItem book, {
  String? fromSeries,
}) {
  final isComic = book.type == BookType.comic;
  final query = <String, String>{
    'type': isComic ? 'Comic' : 'Novel',
    if (isComic) 'seriesTitle': book.seriesTitle ?? book.title,
    if (fromSeries != null && fromSeries.isNotEmpty) 'fromSeries': fromSeries,
  };
  context.push(
    Uri(path: '/book/${book.id}', queryParameters: query).toString(),
  );
}

/// 目录与榜单共用的书籍网格，基于通用分页网格外壳。
class BookGrid extends StatelessWidget {
  const BookGrid({
    super.key,
    required this.books,
    required this.onOpen,
    required this.onRefresh,
    this.header,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.onLoadMore,
    this.loadMoreError,
    this.errorMessage,
    this.onRetry,
    this.showRank = false,
    this.emptyIcon = Icons.menu_book_outlined,
    this.emptyTitle = '暂无内容',
    this.emptyDescription,
  });

  final List<BookListItem> books;
  final void Function(BookListItem book) onOpen;
  final Future<void> Function() onRefresh;
  final Widget? header;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final String? loadMoreError;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool showRank;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyDescription;

  @override
  Widget build(BuildContext context) => PagedGrid<BookListItem>(
    items: books,
    header: header,
    loading: loading,
    loadingMore: loadingMore,
    hasMore: hasMore,
    onLoadMore: onLoadMore,
    loadMoreError: loadMoreError,
    errorMessage: errorMessage,
    onRetry: onRetry,
    onRefresh: onRefresh,
    emptyIcon: emptyIcon,
    emptyTitle: emptyTitle,
    emptyDescription: emptyDescription,
    itemBuilder: (book, index, coverHeight) => BookCoverGridItem.fromBook(
      book,
      key: ValueKey<int>(book.id),
      rank: showRank ? index + 1 : null,
      coverHeight: coverHeight,
      onTap: () => onOpen(book),
    ),
  );
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
      final visible = books.take(layout.columns * maxRows).toList();
      return _gridRows(
        layout: layout,
        itemCount: visible.length,
        itemBuilder: (index) => BookCoverGridItem.fromBook(
          visible[index],
          coverHeight: layout.coverHeight,
          rank: showRank ? index + 1 : null,
          onTap: () => onOpen(visible[index]),
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
