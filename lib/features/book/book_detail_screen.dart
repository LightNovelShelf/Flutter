import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/read_position_cache.dart';
import '../../shared/format.dart';
import '../../shared/widgets/state_views.dart';
import '../search/search_providers.dart';
import 'book_providers.dart';
import 'widgets/book_action_row.dart';
import 'widgets/book_detail_hero.dart';
import 'widgets/book_detail_skeleton.dart';
import 'widgets/book_html_content.dart';
import 'widgets/book_introduction_sheet.dart';
import 'widgets/book_uploader_sheet.dart';
import 'widgets/cover_palette_theme.dart';

const double _collapsedIntroHeight = 90;

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({
    super.key,
    required this.id,
    this.type,
    this.seriesTitle,
  });

  final int id;
  final BookType? type;
  final String? seriesTitle;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  BookDetailRequest get _request => (id: widget.id, type: widget.type);

  String _seriesTitleOf(BookDetailBundle bundle) {
    final hinted = widget.seriesTitle?.trim();
    if (hinted != null && hinted.isNotEmpty) return hinted;
    final classification = bundle.detail.classification;
    return classification.seriesName ??
        classification.seriesNameCn ??
        bundle.detail.title;
  }

  Future<void> _openReader(BookDetailBundle bundle, int sortNum) async {
    final isComic = bundle.isComic;
    await context.push(
      '/reader/${widget.id}/$sortNum${isComic ? '?type=Comic' : ''}',
    );
    // 阅读器把进度写进了 ReadPositionCache，回来要立刻反映。
    if (mounted) setState(() {});
  }

  void _openComments(BookDetailBundle bundle) {
    final isComic = bundle.isComic;
    final query = <String, String>{
      'title': bundle.detail.title,
      'target': isComic ? 'Series' : 'Book',
      if (isComic) 'seriesTitle': _seriesTitleOf(bundle),
    };
    context.push(
      Uri(
        path: '/book/${widget.id}/comments',
        queryParameters: query,
      ).toString(),
    );
  }

  void _searchTag(String tag, bool isComic) {
    ref
        .read(bookSearchProvider.notifier)
        .seed(query: tag, mode: BookSearchMode.tags, comic: isComic);
    context.go('/search');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final async = ref.watch(bookDetailProvider(_request));
    final bundle = async.value;

    return CoverPaletteTheme(
      coverUrl: bundle?.detail.coverUrl ?? '',
      blurHash: bundle?.detail.coverPlaceholder,
      settings: settings,
      child: Builder(
        builder: (themedContext) => Scaffold(
          body: async.when(
            loading: () => const BookDetailSkeleton(),
            error: (error, _) => Center(
              child: ErrorStateView(
                title: '无法加载这本书',
                message: error is ApiError ? error.message : '请稍后再试。',
                onRetry: () => ref.invalidate(bookDetailProvider(_request)),
              ),
            ),
            data: (value) => _body(themedContext, value),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, BookDetailBundle bundle) {
    final detail = bundle.detail;
    final colors = Theme.of(context).colorScheme;
    final position = ReadPositionCache.merge(widget.id, detail.readPosition);
    final currentIndex = position == null
        ? -1
        : detail.chapters.indexWhere(
            (chapter) => chapter.id == position.chapterId,
          );

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          expandedHeight: bookHeroHeight,
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.mode_comment_outlined),
              tooltip: '评论',
              onPressed: () => _openComments(bundle),
            ),
            if (bundle.isComic)
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  if (value == 'versions') {
                    context.push(
                      Uri(
                        path: '/book/${widget.id}/versions',
                        queryParameters: <String, String>{
                          'seriesTitle': _seriesTitleOf(bundle),
                        },
                      ).toString(),
                    );
                    return;
                  }
                  // 用 State 的 context：弹窗要沿用应用主题，不跟着封面取色走。
                  showBookUploaderSheet(this.context, detail.user);
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'versions',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.library_books_outlined),
                      title: Text('其它版本'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'uploader',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_outline),
                      title: Text('上传者'),
                    ),
                  ),
                ],
              )
            else
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: '上传者',
                onPressed: () =>
                    showBookUploaderSheet(this.context, detail.user),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: BookHero(detail: detail),
            collapseMode: CollapseMode.parallax,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              _stats(context, detail),
              const SizedBox(height: 16),
              BookActionRow(
                bookId: widget.id,
                bundle: bundle,
                currentIndex: currentIndex,
                onRead: (sortNum) => _openReader(bundle, sortNum),
              ),
              if (detail.introduction.trim().isNotEmpty)
                _introduction(context, detail),
              if (detail.classification.tags.isNotEmpty) _tags(context, bundle),
              const SizedBox(height: 24),
              _updateStrip(context, detail),
              const SizedBox(height: 24),
              Text(
                '章节',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _chapterRow(
                context,
                bundle,
                index,
                isCurrent: index == currentIndex,
              ),
              childCount: detail.chapters.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }

  Widget _stats(BuildContext context, BookDetail detail) {
    final colors = Theme.of(context).colorScheme;
    Widget chip(IconData icon, String label) => Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.71),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        chip(Icons.favorite_border, '收藏 ${formatCount(detail.favoriteCount)}'),
        chip(Icons.visibility_outlined, '阅读 ${formatCount(detail.viewCount)}'),
        chip(Icons.schedule, formatRelativeTime(detail.lastUpdatedAt)),
        chip(Icons.menu_book_outlined, '${detail.chapters.length} 章'),
      ],
    );
  }

  Widget _introduction(BuildContext context, BookDetail detail) {
    final colors = Theme.of(context).colorScheme;
    // 带 ruby 的简介不折叠，注音会被切掉半行。
    final clampable = !htmlHasRuby(detail.introduction);
    final content = BookHtmlContent(
      html: detail.introduction,
      preview: clampable,
      textColor: colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '简介',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          if (!clampable)
            content
          else
            ClipRect(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _collapsedIntroHeight,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: 1,
                  child: content,
                ),
              ),
            ),
          if (clampable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showBookIntroductionSheet(context, detail),
                child: const Text('展开'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tags(BuildContext context, BookDetailBundle bundle) {
    final tags = <String>{
      for (final tag in bundle.detail.classification.tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    }.toList();
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          for (final tag in tags)
            ActionChip(
              label: Text(tag),
              labelStyle: const TextStyle(fontSize: 13, height: 18 / 13),
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: () => _searchTag(tag, bundle.isComic),
            ),
        ],
      ),
    );
  }

  Widget _updateStrip(BuildContext context, BookDetail detail) {
    final colors = Theme.of(context).colorScheme;
    final chapter = detail.chapters.isNotEmpty
        ? detail.chapters.last.title
        : detail.lastUpdatedChapter;
    final time = formatRelativeTime(detail.lastUpdatedAt);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.bolt_outlined, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chapter == null || chapter.isEmpty
                  ? '最近更新：${time.isEmpty ? '时间未知' : time}'
                  : '最近更新：${time.isEmpty ? '时间未知' : time} · $chapter',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.46,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterRow(
    BuildContext context,
    BookDetailBundle bundle,
    int index, {
    required bool isCurrent,
  }) {
    final colors = Theme.of(context).colorScheme;
    final chapter = bundle.detail.chapters[index];
    return InkWell(
      onTap: () => _openReader(bundle, index + 1),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.5,
                  color: isCurrent ? colors.primary : colors.onSurfaceVariant,
                  fontFeatures: const <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  letterSpacing: 0.5,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: isCurrent ? colors.primary : colors.onSurface,
                ),
              ),
            ),
            if (isCurrent) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '当前',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
