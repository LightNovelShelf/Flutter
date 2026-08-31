import 'package:flutter/material.dart';

import '../../data/api/models.dart';
import '../layout/book_grid_layout.dart';
import '../paging/identity_child_delegate.dart';
import '../paging/scroll_prefetch.dart';
import 'book_cover_grid_item.dart';
import 'book_grid_slivers.dart';
import 'state_views.dart';

/// 分页网格外壳：下拉刷新、触底加载、骨架/空/错误态，卡片由 [itemBuilder] 构建。
class PagedGrid<T> extends StatelessWidget {
  const PagedGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onRefresh,
    this.header,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.onLoadMore,
    this.loadMoreError,
    this.errorMessage,
    this.onRetry,
    this.emptyIcon = Icons.menu_book_outlined,
    this.emptyTitle = '暂无内容',
    this.emptyDescription,
    this.revision,
  });

  /// 目录与榜单共用的书籍网格。
  static PagedGrid<BookListItem> books({
    Key? key,
    required List<BookListItem> books,
    required void Function(BookListItem book) onOpen,
    required Future<void> Function() onRefresh,
    Widget? header,
    bool loading = false,
    bool loadingMore = false,
    bool hasMore = false,
    VoidCallback? onLoadMore,
    String? loadMoreError,
    String? errorMessage,
    VoidCallback? onRetry,
    bool showRank = false,
    IconData emptyIcon = Icons.menu_book_outlined,
    String emptyTitle = '暂无内容',
    String? emptyDescription,
  }) => PagedGrid<BookListItem>(
    key: key,
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

  final List<T> items;

  /// `coverHeight` 是卡片封面区的高度，卡片据此向图床要尺寸档。
  final Widget Function(T item, int index, double coverHeight) itemBuilder;

  final Future<void> Function() onRefresh;
  final Widget? header;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final String? loadMoreError;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyDescription;

  /// 影响卡片外观但不改变 [items] 的状态；变化时强制网格重建可见卡片。
  final Object? revision;

  static const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(20, 12, 20, 0);

  void _loadMore() {
    if (!hasMore || loading || loadingMore) return;
    onLoadMore?.call();
  }

  @override
  Widget build(BuildContext context) {
    final windowHeight = MediaQuery.sizeOf(context).height;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = BookGridLayout.of(constraints.maxWidth);
          return PrefetchOnScroll(
            onLoadMore: _loadMore,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                if (header != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(child: header),
                  ),
                ..._contentSlivers(layout, windowHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _contentSlivers(BookGridLayout layout, double windowHeight) {
    if (items.isEmpty) {
      if (loading) {
        return <Widget>[
          bookGridSkeletonSliver(
            layout: layout,
            count: layout.skeletonCount(windowHeight),
            padding: _gridPadding,
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

    return <Widget>[
      SliverPadding(
        padding: _gridPadding,
        sliver: SliverGrid(
          gridDelegate: layout.tileGridDelegate(),
          delegate: IdentityChildDelegate<T>(
            items: items,
            revision: (layout.coverHeight, revision),
            itemBuilder: (context, item, index) =>
                itemBuilder(item, index, layout.coverHeight),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 40),
        sliver: SliverToBoxAdapter(
          child: onLoadMore == null
              ? const SizedBox(height: 8)
              : SizedBox(
                  height: 58,
                  child: ListFooterStatus(
                    loading: loadingMore,
                    hasMore: hasMore,
                    error: loadMoreError,
                    onRetry: onLoadMore,
                  ),
                ),
        ),
      ),
    ];
  }
}
