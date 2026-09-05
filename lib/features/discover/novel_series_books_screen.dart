import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
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
      ),
      body: PagedGrid.books(
        header: NovelOrderSelector(
          order: _order,
          onChanged: (order) => setState(() => _order = order),
        ),
        books: state.items,
        loading: state.loading,
        loadingMore: state.loadingMore,
        hasMore: state.hasMore && state.loadMoreError == null,
        loadMoreError: state.loadMoreError,
        errorMessage: state.error,
        onRetry: controller.retry,
        onRefresh: controller.refresh,
        onLoadMore: controller.loadMore,
        onOpen: (book) => openBookDetail(context, book),
        emptyIcon: Icons.menu_book_outlined,
        emptyTitle: '暂无书籍',
        emptyDescription: '该系列下暂无可显示的小说。',
      ),
    );
  }
}
