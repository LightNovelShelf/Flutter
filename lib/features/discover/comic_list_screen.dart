import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import 'catalog_providers.dart';
import 'widgets/book_grid.dart';

/// 全部漫画列表，不做内容过滤。
class ComicListScreen extends ConsumerStatefulWidget {
  const ComicListScreen({super.key});

  @override
  ConsumerState<ComicListScreen> createState() => _ComicListScreenState();
}

class _ComicListScreenState extends ConsumerState<ComicListScreen> {
  ComicOrder _order = ComicOrder.latest;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comicCatalogProvider(_order));
    final controller = ref.read(comicCatalogProvider(_order).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('全部漫画')),
      body: BookGrid(
        header: SegmentedButton<ComicOrder>(
          segments: const <ButtonSegment<ComicOrder>>[
            ButtonSegment<ComicOrder>(
              value: ComicOrder.latest,
              label: Text('最新更新'),
            ),
            ButtonSegment<ComicOrder>(
              value: ComicOrder.newest,
              label: Text('最新上架'),
            ),
            ButtonSegment<ComicOrder>(
              value: ComicOrder.view,
              label: Text('最多阅读'),
            ),
          ],
          selected: <ComicOrder>{_order},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _order = selection.first),
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
        emptyIcon: Icons.image_not_supported_outlined,
        emptyTitle: '暂无漫画',
        emptyDescription: '当前排序下暂无可显示的漫画。',
      ),
    );
  }
}
