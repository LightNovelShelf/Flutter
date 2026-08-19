import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../../app/theme/app_theme.dart';
import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/read_position_cache.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/cover_seed.dart';
import '../../shared/format.dart';
import '../../shared/image_cache.dart';
import '../../shared/image_sizing.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/widgets/book_image.dart';
import '../../shared/widgets/image_preview.dart';
import '../../shared/widgets/state_views.dart';
import '../search/search_providers.dart';
import 'book_providers.dart';
import 'widgets/book_html_content.dart';
import 'widgets/comment_thread.dart';

const double _heroHeight = 280;

/// 详情页封面的显示高度。模糊底图、主封面、取色三处共用它，好让三者算出同一个
/// 尺寸档、同一个缓存键 —— 整页只下载并解码一张封面。
///
/// 主封面外层容器固定 100×150，是三者里唯一对清晰度有要求的，所以按它定档。
/// 改这里之前先确认三处仍然共用，否则会静默退化成多次下载。
const double _coverDisplayHeight = 150;
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
  bool _shelfBusy = false;
  bool? _shelfOverride;
  String? _shelfError;
  String? _paletteKey;
  Color? _coverSeed;

  BookDetailRequest get _request => (id: widget.id, type: widget.type);

  /// BlurHash 已经包含封面的低频色彩信息，优先用它取色，避免为主题额外下载原图。
  void _syncPalette({
    required String coverUrl,
    required String? blurHash,
    required bool enabled,
  }) {
    if (!enabled) return;
    final hash = blurHash?.trim();
    final hasBlurHash = hash != null && hash.isNotEmpty;
    if (!hasBlurHash && coverUrl.isEmpty) return;

    final key = hasBlurHash ? 'blur:$hash' : 'url:$coverUrl';
    if (key == _paletteKey) return;
    _paletteKey = key;
    _coverSeed = null;

    // 取色本身只要 96×144，但刻意跟主封面要同一档：那张图整页反正都要下，
    // 复用它等于零额外请求，比单独要一张最小档更省。
    final ImageProvider<Object> provider;
    if (hasBlurHash) {
      provider = BlurHashImage(hash, decodingWidth: 32, decodingHeight: 48);
    } else {
      final sized = sizedImageUrl(
        coverUrl,
        logicalHeight: _coverDisplayHeight,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      provider = CachedNetworkImageProvider(
        sized,
        cacheKey: BookImage.cacheKeyFor(sized),
        cacheManager: appImageCacheManager,
      );
    }
    resolveCoverSeedColor(
          provider,
          size: hasBlurHash ? const Size(32, 48) : const Size(96, 144),
        )
        .then((color) {
          if (!mounted || _paletteKey != key) return;
          if (color == null) return;
          setState(() => _coverSeed = color);
        })
        .catchError((Object _) {
          // 取色失败沿用应用主题。
        });
  }

  ThemeData _theme(BuildContext context, AppSettings settings) {
    final base = Theme.of(context);
    final seed = settings.coverColorExtraction ? _coverSeed : null;
    if (seed == null) return base;
    final hex = seed.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    return buildAppTheme(
      brightness: base.brightness,
      settings: settings.copyWith(
        seedColorValue: '#${hex.toUpperCase()}',
        useSystemColor: false,
      ),
    );
  }

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

  Future<void> _toggleShelf(bool inShelf) async {
    setState(() {
      _shelfBusy = true;
      _shelfError = null;
      _shelfOverride = !inShelf;
    });
    try {
      final result = await ref
          .read(shelfProvider.notifier)
          .toggleBook(widget.id);
      if (!mounted) return;
      setState(() {
        _shelfBusy = false;
        _shelfOverride = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _shelfBusy = false;
        _shelfOverride = null;
        _shelfError = _describeShelfError(error);
      });
    }
  }

  static String _describeShelfError(Object error) {
    if (error is ApiError) {
      return switch (error.category) {
        ApiErrorCategory.auth => '请重新登录后使用书架。',
        ApiErrorCategory.network => '离线时无法修改书架。',
        _ => error.message,
      };
    }
    return '无法更新书架。';
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

  void _showUploader(BookDetailUser? user) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        final text = Theme.of(sheetContext).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.account_circle_outlined,
                      size: 22,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '上传者信息',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    CommentAvatar(
                      url: user?.avatarUrl ?? '',
                      name: user?.userName ?? '?',
                      size: 56,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            user?.userName.isNotEmpty == true
                                ? user!.userName
                                : '未知上传者',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user == null ? '没有上传者资料' : '书籍上传者',
                            style: text.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (user != null && user.id > 0) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.badge_outlined,
                          size: 20,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'UID',
                              style: text.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            SelectableText(
                              '${user.id}',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showIntroduction(BuildContext context, BookDetail detail) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 1,
        snap: true,
        snapSizes: const <double>[0.7, 1],
        builder: (sheetContext, controller) {
          final colors = Theme.of(sheetContext).colorScheme;
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.subject, size: 22, color: colors.primary),
                  const SizedBox(width: 10),
                  const Text(
                    '简介',
                    style: TextStyle(
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BookHtmlContent(
                html: detail.introduction,
                textColor: colors.onSurfaceVariant,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final async = ref.watch(bookDetailProvider(_request));
    final bundle = async.value;
    if (bundle != null) {
      _syncPalette(
        coverUrl: bundle.detail.coverUrl,
        blurHash: bundle.detail.coverPlaceholder,
        enabled: settings.coverColorExtraction,
      );
    }

    return Theme(
      data: _theme(context, settings),
      child: Builder(
        builder: (themedContext) => Scaffold(
          body: async.when(
            loading: () => const _BookDetailLoading(),
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
          expandedHeight: _heroHeight,
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
                  _showUploader(detail.user);
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
                onPressed: () => _showUploader(detail.user),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: _BookHero(detail: detail),
            collapseMode: CollapseMode.parallax,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              _stats(context, detail),
              const SizedBox(height: 16),
              _actions(context, bundle, currentIndex),
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

  Widget _actions(
    BuildContext context,
    BookDetailBundle bundle,
    int currentIndex,
  ) {
    final colors = Theme.of(context).colorScheme;
    final detail = bundle.detail;
    final hasChapters = detail.chapters.isNotEmpty;
    final resolvedInShelf =
        _shelfOverride ??
        ref.watch(bookInShelfProvider(widget.id)).value ??
        false;
    final continueTitle = currentIndex >= 0
        ? cleanChapterTitle(detail.chapters[currentIndex].title)
        : null;
    final label = continueTitle == null
        ? '开始阅读'
        : '继续 · ${continueTitle.length > 15 ? '${continueTitle.substring(0, 15)}…' : continueTitle}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 漫画按系列聚合，没有单卷书架条目。
            if (!bundle.isComic) ...<Widget>[
              SizedBox(
                width: 56,
                height: 56,
                child: Material(
                  color: resolvedInShelf
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _shelfBusy
                        ? null
                        : () => _toggleShelf(resolvedInShelf),
                    child: Center(
                      child: _shelfBusy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : Icon(
                              resolvedInShelf
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              size: 25,
                              color: resolvedInShelf
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: hasChapters
                      ? () => _openReader(
                          bundle,
                          currentIndex >= 0 ? currentIndex + 1 : 1,
                        )
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_shelfError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _shelfError!,
              style: TextStyle(fontSize: 13, height: 1.38, color: colors.error),
            ),
          ),
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
                onPressed: () => _showIntroduction(context, detail),
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

class _BookHero extends StatelessWidget {
  const _BookHero({required this.detail});

  final BookDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final category = detail.category;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: colors.surface),
        if (detail.coverUrl.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Opacity(
              opacity: 0.65,
              // 28px 高斯模糊后细节全失，本可以只要最小档；但主封面那张整页反正
              // 都要下，跟它同档就能直接复用，多下一张最小档反而更亏。
              child: BookImage(
                url: detail.coverUrl,
                displayHeight: _coverDisplayHeight,
                blurHash: detail.coverPlaceholder,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors.surface.withValues(alpha: 0.1),
                colors.surface.withValues(alpha: 0.55),
                colors.surface,
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                width: _coverDisplayHeight * BookGridLayout.coverAspectRatio,
                height: _coverDisplayHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: colors.surfaceContainerHighest,
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x2D000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: detail.coverUrl.isEmpty
                    ? Icon(
                        Icons.menu_book_outlined,
                        size: 40,
                        color: colors.onSurfaceVariant,
                      )
                    : Builder(
                        builder: (context) => GestureDetector(
                          onTap: () => unawaited(
                            showImagePreview(
                              context,
                              url: detail.coverUrl,
                              sourceRect: globalRectOf(context),
                            ),
                          ),
                          child: BookImage(
                            url: detail.coverUrl,
                            displayHeight: _coverDisplayHeight,
                            blurHash: detail.coverPlaceholder,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      detail.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(
                        fontSize: 22,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (detail.authorName != null &&
                        detail.authorName!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        detail.authorName!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (category != null && category.shortName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.shortName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookDetailLoading extends StatelessWidget {
  const _BookDetailLoading();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double height, double radius, {double widthFactor = 1}) =>
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: block,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      bar(28, 8, widthFactor: 0.88),
                      const SizedBox(height: 9),
                      bar(15, 8, widthFactor: 0.42),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                SizedBox(width: 58, child: bar(26, 8)),
                const SizedBox(width: 8),
                SizedBox(width: 58, child: bar(26, 8)),
                const SizedBox(width: 8),
                SizedBox(width: 92, child: bar(26, 8)),
              ],
            ),
            const SizedBox(height: 20),
            bar(56, 16),
            const SizedBox(height: 20),
            bar(88, 8),
            const SizedBox(height: 20),
            bar(42, 12),
          ],
        ),
      ),
    );
  }
}
