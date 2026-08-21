import 'package:flutter/material.dart';

import '../layout/book_grid_layout.dart';
import 'book_cover_grid_item.dart';
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
  });

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

    return <Widget>[
      SliverPadding(
        padding: _gridPadding,
        sliver: SliverGrid(
          gridDelegate: _delegate(layout),
          delegate: _PagedGridChildDelegate<T>(
            items: items,
            itemBuilder: itemBuilder,
            coverHeight: layout.coverHeight,
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

  SliverGridDelegate _delegate(BookGridLayout layout) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.columns,
        crossAxisSpacing: BookGridLayout.columnGap,
        mainAxisSpacing: BookGridLayout.rowGap,
        childAspectRatio: layout.childAspectRatio,
      );
}

/// 分页状态变化时复用现有子节点，只有数据列表或卡片尺寸变化才重建网格项。
///
/// `SliverGrid.builder` 每次父级 build 都会创建默认必定重建的 delegate。
class _PagedGridChildDelegate<T> extends SliverChildBuilderDelegate {
  _PagedGridChildDelegate({
    required this.items,
    required this.itemBuilder,
    required this.coverHeight,
  }) : super(
         (context, index) => itemBuilder(items[index], index, coverHeight),
         childCount: items.length,
         addAutomaticKeepAlives: false,
       );

  final List<T> items;
  final Widget Function(T item, int index, double coverHeight) itemBuilder;
  final double coverHeight;

  @override
  bool shouldRebuild(covariant _PagedGridChildDelegate<T> oldDelegate) =>
      !identical(items, oldDelegate.items) ||
      coverHeight != oldDelegate.coverHeight;
}
