import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/widgets/book_cover_grid_item.dart';
import '../../shared/widgets/state_views.dart';
import 'search_providers.dart';

const Map<BookSearchMode, String> _modeLabels = <BookSearchMode, String>{
  BookSearchMode.fuzzy: '模糊',
  BookSearchMode.exact: '精确',
  BookSearchMode.title: '标题',
  BookSearchMode.author: '作者',
  BookSearchMode.name: '系列',
  BookSearchMode.tags: '标签',
};

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

  /// 只有「空/非空」翻转才需要重建（清空按钮显隐）。
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

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 600) {
      ref.read(bookSearchProvider.notifier).loadMore();
    }
    return false;
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
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(bookSearchProvider);
    final controller = ref.read(bookSearchProvider.notifier);
    final layout = BookGridLayout.of(MediaQuery.sizeOf(context).width);

    // 详情页标签跳转直接改写 provider，输入框要跟上外部提交的关键词。
    ref.listen<BookSearchState>(bookSearchProvider, (previous, next) {
      if (previous?.query == next.query) return;
      if (_input.text.trim() == next.query) return;
      _input.text = next.query;
      _input.selection = TextSelection.collapsed(offset: next.query.length);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: TextField(
          controller: _input,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: controller.onInputChanged,
          onSubmitted: (value) {
            _focus.unfocus();
            controller.submit(value);
          },
          decoration: InputDecoration(
            hintText: '搜索小说和漫画',
            isDense: true,
            filled: true,
            fillColor: colors.surfaceContainerHighest,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: !_hasInput
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: '清空',
                    onPressed: () {
                      _input.clear();
                      controller.onInputChanged('');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          for (final entry in _modeLabels.entries) ...<Widget>[
                            ChoiceChip(
                              label: Text(
                                entry.value,
                                maxLines: 1,
                                softWrap: false,
                              ),
                              selected: state.mode == entry.key,
                              onSelected: (_) => controller.setMode(entry.key),
                            ),
                            if (entry.key != _modeLabels.keys.last)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(value: false, label: Text('小说')),
                        ButtonSegment<bool>(value: true, label: Text('漫画')),
                      ],
                      selected: <bool>{state.comic},
                      onSelectionChanged: (selection) =>
                          controller.setComic(selection.first),
                    ),
                    if (state.isIdle) _history(),
                    if (!state.isIdle && !state.loading && state.error == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          '${state.comic ? '漫画' : '小说'} · 第 '
                          '${state.page < 1 ? 1 : state.page} / '
                          '${state.totalPages < 1 ? 1 : state.totalPages} 页',
                          style: text.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            ..._results(state, layout),
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

  Widget _history() {
    final history = ref.watch(searchHistoryProvider).valueOrNull;
    if (history == null || history.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '最近搜索',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '清除搜索历史',
                onPressed: ref.read(searchHistoryProvider.notifier).clear,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final keyword in history)
                InputChip(
                  label: Text(keyword),
                  onPressed: () => _useKeyword(keyword),
                  onDeleted: () =>
                      ref.read(searchHistoryProvider.notifier).remove(keyword),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _results(BookSearchState state, BookGridLayout layout) {
    if (state.error != null && state.items.isEmpty) {
      return <Widget>[
        SliverToBoxAdapter(
          child: ErrorStateView(
            title: '搜索失败',
            message: state.error!,
            onRetry: ref.read(bookSearchProvider.notifier).retry,
          ),
        ),
      ];
    }

    if (state.loading && state.items.isEmpty) {
      return <Widget>[
        _grid(
          layout,
          itemCount: layout.skeletonCount(MediaQuery.sizeOf(context).height),
          builder: (_, _) => const BookGridSkeletonTile(),
        ),
      ];
    }

    if (state.isIdle) {
      final history = ref.watch(searchHistoryProvider).valueOrNull;
      if (history != null && history.isNotEmpty) {
        return const <Widget>[SliverToBoxAdapter(child: SizedBox.shrink())];
      }
      return const <Widget>[
        SliverToBoxAdapter(
          child: EmptyStateView(
            icon: Icons.search,
            title: '搜索小说和漫画',
            description: '选择模式，然后输入书名、作者、系列或标签。',
          ),
        ),
      ];
    }

    if (state.items.isEmpty) {
      return const <Widget>[
        SliverToBoxAdapter(
          child: EmptyStateView(
            icon: Icons.search_off,
            title: '未找到结果',
            description: '请尝试其他搜索模式或关键词。',
          ),
        ),
      ];
    }

    final placeholders = state.loadingMore
        ? layout.loadMorePlaceholderCount(state.items.length)
        : 0;
    return <Widget>[
      _grid(
        layout,
        itemCount: state.items.length + placeholders,
        builder: (context, index) {
          if (index >= state.items.length) return const BookGridSkeletonTile();
          final item = state.items[index];
          return BookCoverGridItem.fromBook(
            item,
            coverHeight: layout.coverHeight,
            onTap: () => _openBook(item),
          );
        },
      ),
      if (state.error != null)
        SliverToBoxAdapter(
          child: ListFooterStatus(
            loading: false,
            hasMore: state.hasMore,
            error: state.error,
            onRetry: ref.read(bookSearchProvider.notifier).loadMore,
          ),
        ),
    ];
  }

  Widget _grid(
    BookGridLayout layout, {
    required int itemCount,
    required Widget Function(BuildContext context, int index) builder,
  }) => SliverPadding(
    padding: const EdgeInsets.symmetric(
      horizontal: BookGridLayout.horizontalPadding,
    ),
    sliver: SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.columns,
        crossAxisSpacing: BookGridLayout.columnGap,
        mainAxisSpacing: BookGridLayout.rowGap,
        childAspectRatio: layout.childAspectRatio,
      ),
      delegate: SliverChildBuilderDelegate(builder, childCount: itemCount),
    ),
  );
}
