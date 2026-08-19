import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_cover_grid_item.dart';
import '../../../shared/widgets/state_views.dart';

/// 打开书籍详情：漫画必须带上系列名，详情页据此拉取系列信息。
void openBookDetail(BuildContext context, BookListItem book) {
  final isComic = book.type == BookType.comic;
  final query = <String, String>{
    'type': isComic ? 'Comic' : 'Novel',
    if (isComic) 'seriesTitle': book.seriesTitle ?? book.title,
  };
  context.push(Uri(path: '/book/${book.id}', queryParameters: query).toString());
}

/// 目录/榜单共用的网格：下拉刷新 + 触底加载 + 骨架/空/错误态。
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

  static const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(20, 12, 20, 0);

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!hasMore || loading || loadingMore || onLoadMore == null) return false;
    final metrics = notification.metrics;
    // 距底不足 0.6 屏时预取下一页。
    if (metrics.pixels >=
        metrics.maxScrollExtent - metrics.viewportDimension * 0.6) {
      onLoadMore!();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final windowHeight = MediaQuery.sizeOf(context).height;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = BookGridLayout.of(constraints.maxWidth);
          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                if (header != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(child: header),
                  ),
                ..._contentSlivers(context, layout, windowHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _contentSlivers(
    BuildContext context,
    BookGridLayout layout,
    double windowHeight,
  ) {
    if (books.isEmpty) {
      if (loading) {
        return <Widget>[
          SliverPadding(
            padding: _gridPadding,
            sliver: SliverGrid.builder(
              gridDelegate: _delegate(layout),
              itemCount: layout.skeletonCount(windowHeight),
              itemBuilder: (_, _) => const BookGridSkeletonTile(),
            ),
          ),
        ];
      }
      final message = errorMessage;
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: message != null
              ? ErrorStateView(message: message, onRetry: onRetry)
              : EmptyStateView(
                  icon: emptyIcon,
                  title: emptyTitle,
                  description: emptyDescription,
                ),
        ),
      ];
    }

    final placeholders =
        loadingMore ? layout.loadMorePlaceholderCount(books.length) : 0;
    return <Widget>[
      SliverPadding(
        padding: _gridPadding,
        sliver: SliverGrid.builder(
          gridDelegate: _delegate(layout),
          itemCount: books.length + placeholders,
          itemBuilder: (context, index) {
            if (index >= books.length) return const BookGridSkeletonTile();
            final book = books[index];
            return BookCoverGridItem.fromBook(
              book,
              rank: showRank ? index + 1 : null,
              onTap: () => onOpen(book),
            );
          },
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 40),
        sliver: SliverToBoxAdapter(
          // 不分页的列表（榜单）没有底部状态可言，只留下边距。
          child: onLoadMore == null
              ? const SizedBox(height: 8)
              : ListFooterStatus(
                  loading: false,
                  hasMore: hasMore || loadingMore,
                  error: loadMoreError,
                  onRetry: onLoadMore,
                ),
        ),
      ),
    ];
  }

  SliverGridDelegate _delegate(BookGridLayout layout) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.columns,
        crossAxisSpacing: BookGridLayout.columnGap,
        mainAxisSpacing: BookGridLayout.rowGap,
        childAspectRatio: layout.childAspectRatio,
      );
}

/// 首页分区里的静态网格：不滚动，按父级宽度自行分列。
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
          // 父级已经扣掉内边距，这里不再重复扣。
          final layout =
              BookGridLayout.of(constraints.maxWidth, horizontalPadding: 0);
          final visible = books.take(layout.columns * maxRows).toList();
          return _gridRows(
            layout: layout,
            itemCount: visible.length,
            itemBuilder: (index) => BookCoverGridItem.fromBook(
              visible[index],
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
          final layout =
              BookGridLayout.of(constraints.maxWidth, horizontalPadding: 0);
          return _gridRows(
            layout: layout,
            itemCount: layout.columns * rows,
            itemBuilder: (_) => const BookGridSkeletonTile(),
          );
        },
      );
}

/// 手动按行摆放，保证残行的卡片仍然左对齐且与整行同宽。
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
