import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/models.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/book_cover_grid_item.dart';
import '../../shared/widgets/book_grid_slivers.dart';
import '../../shared/widgets/state_views.dart';
import 'search_providers.dart';
import 'widgets/search_filters.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasInput = false;

  @override
  void initState() {
    super.initState();
    _input.text = ref.read(bookSearchProvider).query;
    _hasInput = _input.text.isNotEmpty;
    _input.addListener(_syncInputState);
  }

  /// 仅在输入由空变非空或反之时重建，用于清空按钮显隐。
  void _syncInputState() {
    final hasInput = _input.text.isNotEmpty;
    if (hasInput == _hasInput) return;
    setState(() => _hasInput = hasInput);
  }

  @override
  void dispose() {
    _input.removeListener(_syncInputState);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _loadMore() {
    final state = ref.read(bookSearchProvider);
    if (state.loading || state.loadingMore || !state.hasMore) return;
    if (state.error != null) return;
    ref.read(bookSearchProvider.notifier).loadMore();
  }

  void _openBook(BookListItem item) {
    final isComic = item.type == BookType.comic;
    final query = <String, String>{
      'type': isComic ? 'Comic' : 'Novel',
      if (isComic) 'seriesTitle': item.title,
    };
    context.push(
      Uri(path: '/book/${item.id}', queryParameters: query).toString(),
    );
  }

  void _useKeyword(String keyword) {
    _input.text = keyword;
    _input.selection = TextSelection.collapsed(offset: keyword.length);
    _focus.unfocus();
    ref.read(bookSearchProvider.notifier).submit(keyword);
  }

  @override
  Widget build(BuildContext context) {
    // 详情页标签跳转会直接改写 provider，输入框需同步外部提交的关键词。
    ref.listen<BookSearchState>(bookSearchProvider, (previous, next) {
      if (previous?.query == next.query) return;
      if (_input.text.trim() == next.query) return;
      _input.text = next.query;
      _input.selection = TextSelection.collapsed(offset: next.query.length);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: PrefetchOnScroll(
        threshold: 600,
        onLoadMore: _loadMore,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: SearchHeader(
                input: _input,
                focus: _focus,
                hasInput: _hasInput,
                onUseKeyword: _useKeyword,
              ),
            ),
            _SearchResults(onOpenBook: _openBook),
            const _SearchFooter(),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 24 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果网格。只订阅结果列表与首屏态，翻页时已建卡片由 delegate 守卫复用。
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.onOpenBook});

  static const EdgeInsets _gridPadding = EdgeInsets.symmetric(
    horizontal: BookGridLayout.horizontalPadding,
  );

  final void Function(BookListItem item) onOpenBook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (items, loading, loadingMore, idle, error) = ref.watch(
      bookSearchProvider.select(
        (state) => (
          state.items,
          state.loading,
          state.loadingMore,
          state.isIdle,
          state.error,
        ),
      ),
    );
    final media = MediaQuery.sizeOf(context);
    final layout = BookGridLayout.of(media.width);

    if (error != null && items.isEmpty) {
      return SliverToBoxAdapter(
        child: ErrorStateView(
          title: '搜索失败',
          message: error,
          onRetry: ref.read(bookSearchProvider.notifier).retry,
        ),
      );
    }

    if (loading && items.isEmpty) {
      return bookGridSkeletonSliver(
        layout: layout,
        count: layout.skeletonCount(media.height),
        padding: _gridPadding,
      );
    }

    if (idle) {
      final history = ref.watch(searchHistoryProvider).value;
      if (history != null && history.isNotEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      return const SliverToBoxAdapter(
        child: EmptyStateView(
          icon: Icons.search,
          title: '搜索小说和漫画',
          description: '选择模式，然后输入书名、作者、系列或标签。',
        ),
      );
    }

    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: EmptyStateView(
          icon: Icons.search_off,
          title: '未找到结果',
          description: '请尝试其他搜索模式或关键词。',
        ),
      );
    }

    final coverHeight = layout.coverHeight;
    return SliverPadding(
      padding: _gridPadding,
      sliver: SliverGrid(
        gridDelegate: layout.tileGridDelegate(),
        delegate: IdentityChildDelegate<BookListItem>(
          items: items,
          revision: (coverHeight,),
          trailingCount: loadingMore
              ? layout.loadMorePlaceholderCount(items.length)
              : 0,
          trailingBuilder: (_, _) => const BookGridSkeletonTile(),
          itemBuilder: (_, item, _) => BookCoverGridItem.fromBook(
            item,
            coverHeight: coverHeight,
            onTap: () => onOpenBook(item),
          ),
        ),
      ),
    );
  }
}

/// 翻页出错时的重试条，结果为空时由错误态视图接管。
class _SearchFooter extends ConsumerWidget {
  const _SearchFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (error, hasMore, empty) = ref.watch(
      bookSearchProvider.select(
        (state) => (state.error, state.hasMore, state.items.isEmpty),
      ),
    );
    if (error == null || empty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: ListFooterStatus(
        loading: false,
        hasMore: hasMore,
        error: error,
        onRetry: ref.read(bookSearchProvider.notifier).loadMore,
      ),
    );
  }
}
