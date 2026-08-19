import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import 'discover_providers.dart';
import 'widgets/book_grid.dart';

/// 全部小说：排序切换 + 无限滚动。
class BookListScreen extends ConsumerStatefulWidget {
  const BookListScreen({super.key});

  @override
  ConsumerState<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends ConsumerState<BookListScreen> {
  BookListOrder _order = BookListOrder.latest;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookCatalogProvider(_order));
    final controller = ref.read(bookCatalogProvider(_order).notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('全部小说')),
      body: BookGrid(
        header: SegmentedButton<BookListOrder>(
          segments: const <ButtonSegment<BookListOrder>>[
            ButtonSegment<BookListOrder>(
              value: BookListOrder.latest,
              label: Text('最新更新'),
            ),
            ButtonSegment<BookListOrder>(
              value: BookListOrder.newest,
              label: Text('最新上架'),
            ),
            ButtonSegment<BookListOrder>(
              value: BookListOrder.view,
              label: Text('最多阅读'),
            ),
          ],
          selected: <BookListOrder>{_order},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _order = selection.first),
        ),
        books: state.books,
        loading: state.loading,
        loadingMore: state.loadingMore,
        // 加载更多失败后停止自动预取，交给底部的手动重试。
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
      ),
    );
  }
}
