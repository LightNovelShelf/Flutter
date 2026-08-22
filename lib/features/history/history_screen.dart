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
import 'history_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryTab _tab = HistoryTab.novel;

  static const double _horizontalPadding = 16;
  static const EdgeInsets _gridPadding = EdgeInsets.symmetric(
    horizontal: _horizontalPadding,
  );

  void _openBook(BookListItem book) {
    if (_tab == HistoryTab.comic) {
      // 漫画历史返回的是系列条目，详情页需要系列标题才能拉分卷。
      final title = Uri.encodeComponent(book.title);
      context.push('/book/${book.id}?type=Comic&seriesTitle=$title');
      return;
    }
    context.push('/book/${book.id}?type=Novel');
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空阅读历史'),
        content: const Text('清空后将无法恢复，确定要继续吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(historyProvider.notifier).clear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('阅读历史已清空')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(describeHistoryError(error, fallback: '清空失败，请稍后重试。')),
        ),
      );
    }
  }

  void _loadMore() {
    final data = ref.read(historyProvider).value;
    if (data == null || data.clearing) return;
    final tab = data.tab(_tab);
    if (tab.loadingMore || !tab.hasMore || tab.error != null) return;
    ref.read(historyProvider.notifier).loadMore(_tab);
  }

  Widget _segmentedHeader({required bool enabled}) => Padding(
    padding: const EdgeInsets.fromLTRB(
      _horizontalPadding,
      8,
      _horizontalPadding,
      12,
    ),
    child: SegmentedButton<HistoryTab>(
      segments: const <ButtonSegment<HistoryTab>>[
        ButtonSegment<HistoryTab>(value: HistoryTab.novel, label: Text('小说')),
        ButtonSegment<HistoryTab>(value: HistoryTab.comic, label: Text('漫画')),
      ],
      selected: <HistoryTab>{_tab},
      showSelectedIcon: false,
      onSelectionChanged: enabled
          ? (selection) => setState(() => _tab = selection.first)
          : null,
    ),
  );

  List<Widget> _tabSlivers(
    HistoryState data,
    BookGridLayout layout,
    double height,
  ) {
    final tab = data.tab(_tab);
    final isNovel = _tab == HistoryTab.novel;

    if (tab.items.isEmpty && tab.error != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorStateView(
            message: tab.error!,
            onRetry: () => ref.read(historyProvider.notifier).retry(_tab),
          ),
        ),
      ];
    }

    if (tab.items.isEmpty && tab.isInitialLoading) {
      return <Widget>[_skeletonGrid(layout, height)];
    }

    if (tab.items.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView(
            icon: Icons.history,
            title: '还没有阅读记录',
            description: isNovel ? '读过的小说会出现在这里。' : '看过的漫画会出现在这里。',
          ),
        ),
      ];
    }

    final placeholders = tab.loadingMore
        ? layout.loadMorePlaceholderCount(tab.items.length)
        : 0;
    return <Widget>[
      SliverPadding(
        padding: _gridPadding,
        sliver: SliverGrid(
          gridDelegate: layout.tileGridDelegate(),
          delegate: IdentityChildDelegate<BookListItem>(
            items: tab.items,
            revision: (layout.coverHeight,),
            itemBuilder: (_, book, _) => BookCoverGridItem.fromBook(
              book,
              coverHeight: layout.coverHeight,
              onTap: () => _openBook(book),
            ),
          ),
        ),
      ),
      if (placeholders > 0)
        bookGridSkeletonSliver(
          layout: layout,
          count: placeholders,
          padding: const EdgeInsets.fromLTRB(
            _horizontalPadding,
            BookGridLayout.rowGap,
            _horizontalPadding,
            0,
          ),
        ),
      SliverToBoxAdapter(
        child: ListFooterStatus(
          loading: false,
          hasMore: tab.hasMore,
          error: tab.error,
          endLabel: '没有更多记录了',
          onRetry: () => ref.read(historyProvider.notifier).retry(_tab),
        ),
      ),
    ];
  }

  Widget _skeletonGrid(BookGridLayout layout, double height) =>
      bookGridSkeletonSliver(
        layout: layout,
        count: layout.skeletonCount(height, headerOffset: 150),
        padding: _gridPadding,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(historyProvider);
    final data = async.value;
    final media = MediaQuery.sizeOf(context);
    final layout = BookGridLayout.of(
      media.width,
      horizontalPadding: _horizontalPadding,
    );
    final hasHistory = data != null && !data.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读历史'),
        actions: <Widget>[
          if (hasHistory)
            IconButton(
              tooltip: '清空阅读历史',
              onPressed: data.clearing ? null : _clear,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(historyProvider.notifier).reload(),
        child: data == null
            ? _initialBody(async, layout, media.height)
            // 切换分页要重置预取去重，否则新分页首屏不会触发加载。
            : PrefetchOnScroll(
                key: ValueKey<HistoryTab>(_tab),
                onLoadMore: _loadMore,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: _segmentedHeader(enabled: !data.clearing),
                    ),
                    ..._tabSlivers(data, layout, media.height),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _initialBody(
    AsyncValue<HistoryState> async,
    BookGridLayout layout,
    double height,
  ) {
    if (async.hasError) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorStateView(
              message: describeHistoryError(async.error!),
              onRetry: () => ref.read(historyProvider.notifier).reload(),
            ),
          ),
        ],
      );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(child: _segmentedHeader(enabled: false)),
        _skeletonGrid(layout, height),
      ],
    );
  }
}
