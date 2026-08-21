import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../shared/widgets/paged_grid.dart';
import 'catalog_providers.dart';
import 'widgets/book_grid.dart';
import 'widgets/novel_order_selector.dart';
import 'widgets/novel_series_tile.dart';

/// 全部小说的展示方式：平铺或按系列分组。
enum BookListViewMode { flat, series }

/// 全部小说：展示方式与排序切换，无限滚动。
class BookListScreen extends ConsumerStatefulWidget {
  const BookListScreen({super.key});

  @override
  ConsumerState<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends ConsumerState<BookListScreen> {
  BookListOrder _order = BookListOrder.latest;
  BookListViewMode _mode = BookListViewMode.flat;

  void _openSeries(NovelSeriesListItem series) {
    // 系列名可能带 `/`，走查询参数而不是路径段。
    context.push(
      Uri(
        path: '/books/series',
        queryParameters: <String, String>{
          'name': series.name,
          'order': _order.wire,
        },
      ).toString(),
    );
  }

  Widget _header() => NovelOrderSelector(
    order: _order,
    onChanged: (order) => setState(() => _order = order),
  );

  Widget _flatBody() {
    final state = ref.watch(bookCatalogProvider(_order));
    final controller = ref.read(bookCatalogProvider(_order).notifier);
    return BookGrid(
      header: _header(),
      books: state.items,
      loading: state.loading,
      loadingMore: state.loadingMore,
      // 加载更多失败后停止自动预取，改由底部按钮手动重试。
      hasMore: state.hasMore && state.loadMoreError == null,
      loadMoreError: state.loadMoreError,
      errorMessage: state.error,
      onRetry: controller.retry,
      onRefresh: controller.refresh,
      onLoadMore: controller.loadMore,
      onOpen: (book) => openBookDetail(context, book),
      emptyIcon: Icons.menu_book_outlined,
      emptyTitle: '暂无小说',
      emptyDescription: '当前排序下暂无可显示的小说。',
    );
  }

  Widget _seriesBody() {
    final state = ref.watch(novelSeriesCatalogProvider(_order));
    final controller = ref.read(novelSeriesCatalogProvider(_order).notifier);
    return PagedGrid<NovelSeriesListItem>(
      header: _header(),
      items: state.items,
      loading: state.loading,
      loadingMore: state.loadingMore,
      hasMore: state.hasMore && state.loadMoreError == null,
      loadMoreError: state.loadMoreError,
      errorMessage: state.error,
      onRetry: controller.retry,
      onRefresh: controller.refresh,
      onLoadMore: controller.loadMore,
      itemBuilder: (series, _, coverHeight) => NovelSeriesTile(
        key: ValueKey<String>(series.name),
        series: series,
        coverHeight: coverHeight,
        onTap: () => _openSeries(series),
      ),
      emptyIcon: Icons.folder_open_outlined,
      emptyTitle: '暂无系列',
      emptyDescription: '当前排序下暂无可显示的系列。',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('全部小说'),
      actions: <Widget>[
        _ViewModeMenu(
          mode: _mode,
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: _mode == BookListViewMode.flat ? _flatBody() : _seriesBody(),
  );
}

/// 展示方式切换：标题栏图标按钮加下拉菜单。
class _ViewModeMenu extends StatelessWidget {
  const _ViewModeMenu({required this.mode, required this.onChanged});

  final BookListViewMode mode;
  final ValueChanged<BookListViewMode> onChanged;

  static const Map<BookListViewMode, (IconData, String)> _specs =
      <BookListViewMode, (IconData, String)>{
        BookListViewMode.flat: (Icons.grid_view_outlined, '单本'),
        BookListViewMode.series: (Icons.folder_copy_outlined, '系列'),
      };

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(0, 4),
    builder: (context, controller, _) => IconButton(
      tooltip: '展示方式',
      icon: Icon(_specs[mode]!.$1),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
    menuChildren: <Widget>[
      for (final entry in _specs.entries)
        MenuItemButton(
          leadingIcon: Icon(entry.value.$1),
          trailingIcon: entry.key == mode ? const Icon(Icons.check) : null,
          onPressed: () => onChanged(entry.key),
          child: Text(entry.value.$2),
        ),
    ],
  );
}
