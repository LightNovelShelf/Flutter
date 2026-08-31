import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../shared/widgets/book_cover_grid_item.dart';
import '../../shared/widgets/paged_grid.dart';
import 'catalog_providers.dart';
import 'widgets/book_grid.dart';
import 'widgets/novel_order_selector.dart';

/// 单个小说系列下的全部书籍。
class NovelSeriesBooksScreen extends ConsumerStatefulWidget {
  const NovelSeriesBooksScreen({
    super.key,
    required this.seriesName,
    this.initialOrder = BookListOrder.latest,
  });

  final String seriesName;
  final BookListOrder initialOrder;

  @override
  ConsumerState<NovelSeriesBooksScreen> createState() =>
      _NovelSeriesBooksScreenState();
}

class _NovelSeriesBooksScreenState
    extends ConsumerState<NovelSeriesBooksScreen> {
  late BookListOrder _order = widget.initialOrder;
  final Set<int> _selected = <int>{};
  bool _adding = false;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(BookListItem book) => setState(() {
    if (!_selected.remove(book.id)) _selected.add(book.id);
  });

  Future<void> _selectAll(
    SeriesBooksArg arg,
    SeriesBooksController controller,
  ) async {
    await controller.loadAll();
    if (!mounted) return;
    final books = ref.read(seriesBooksProvider(arg)).items;
    setState(() => _selected
      ..clear()
      ..addAll(books.map((book) => book.id)));
  }

  Future<void> _addSelected() async {
    if (_adding || _selected.isEmpty) return;
    if (!ref.read(authSnapshotProvider).isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再加入书架。')),
      );
      return;
    }
    setState(() => _adding = true);
    try {
      final count = await ref.read(shelfProvider.notifier).addBooks(_selected);
      if (!mounted) return;
      setState(() => _selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count == 0 ? '所选书籍已在书架中' : '已将 $count 本书加入书架'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeShelfError(error, fallback: '无法加入书架。'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arg = (name: widget.seriesName, order: _order);
    final state = ref.watch(seriesBooksProvider(arg));
    final controller = ref.read(seriesBooksProvider(arg).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.seriesName.isEmpty ? '系列' : widget.seriesName,
          overflow: TextOverflow.ellipsis,
        ),
        leading: _selecting
            ? IconButton(
                tooltip: '取消选择',
                onPressed: () => setState(() => _selected.clear()),
                icon: const Icon(Icons.close),
              )
            : null,
        actions: <Widget>[
          if (_selecting) ...<Widget>[
            TextButton(
              onPressed: _adding || state.loadingMore
                  ? null
                  : () => _selectAll(arg, controller),
              child: const Text('全选'),
            ),
            _adding
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: '加入书架',
                    onPressed: _addSelected,
                    icon: const Icon(Icons.library_add_outlined),
                  ),
          ],
        ],
      ),
      body: PagedGrid<BookListItem>(
        revision: (_selected.length, Object.hashAllUnordered(_selected)),
        header: NovelOrderSelector(
          order: _order,
          onChanged: (order) => setState(() => _order = order),
        ),
        items: state.items,
        loading: state.loading,
        loadingMore: state.loadingMore,
        hasMore: state.hasMore && state.loadMoreError == null,
        loadMoreError: state.loadMoreError,
        errorMessage: state.error,
        onRetry: controller.retry,
        onRefresh: controller.refresh,
        onLoadMore: controller.loadMore,
        itemBuilder: (book, _, coverHeight) => BookCoverGridItem.fromBook(
          book,
          key: ValueKey<int>(book.id),
          coverHeight: coverHeight,
          selected: _selected.contains(book.id),
          onLongPress: () => _toggle(book),
          onTap: () => _selecting
              ? _toggle(book)
              : openBookDetail(context, book, fromSeries: widget.seriesName),
        ),
        emptyIcon: Icons.menu_book_outlined,
        emptyTitle: '暂无书籍',
        emptyDescription: '该系列下暂无可显示的小说。',
      ),
    );
  }
}
