import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/read_position_cache.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/image_cache.dart';
import '../../shared/image_sizing.dart';
import '../../shared/widgets/book_image.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/image_preview.dart';
import 'reader_engine.dart';
import 'reader_open_position.dart';
import 'reader_providers.dart';
import 'widgets/comic_retry_tile.dart';
import 'widgets/reader_chapter_sheet.dart';
import 'widgets/reader_chrome.dart';
import 'widgets/reader_settings_sheet.dart';

/// 漫画阅读器：整页图片，按 12 页一批向服务端取图。
class ComicReaderScreen extends ConsumerStatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.bookId,
    required this.sortNum,
  });

  final int bookId;
  final int sortNum;

  @override
  ConsumerState<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends ConsumerState<ComicReaderScreen> {
  static const int _batchSize = 12;
  static const double _unknownAspect = 1.5;

  late final ApiClient _api;
  late final ReaderPositionWriteQueue<ReaderRestorePosition> _positions;
  late final AppLifecycleListener _lifecycle;

  late int _sortNum;
  int _requestVersion = 0;
  bool _loading = true;
  String? _error;
  bool _chromeVisible = false;

  List<ComicChapterSummary> _chapters = const <ComicChapterSummary>[];
  int _chapterIndex = 0;
  ComicChapterSummary? _chapter;
  List<ComicPageSlot> _slots = const <ComicPageSlot>[];
  int _page = 0;
  int _direction = 1;

  final Set<int> _loadingBatches = <int>{};
  final Set<int> _failedBatches = <int>{};

  PageController? _pageController;
  ScrollController? _scrollController;
  ReaderViewMode? _mode;

  @override
  void initState() {
    super.initState();
    _sortNum = widget.sortNum;
    _api = ref.read(apiClientProvider);
    _positions = ReaderPositionWriteQueue<ReaderRestorePosition>(
      _persistPosition,
      fingerprint: (position) => '${position.chapterId}:${position.position}',
    );
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_positions.flush()),
    );
    unawaited(_loadChapter());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_positions.dispose());
    _pageController?.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  Future<void> _persistPosition(ReaderRestorePosition position) async {
    try {
      await _api.saveReadPosition(
        bookId: widget.bookId,
        chapterId: position.chapterId,
        position: position.position,
      );
    } catch (_) {
      // 进度写入失败不打断阅读。
    }
  }

  Future<void> _loadChapter() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
      _loadingBatches.clear();
      _failedBatches.clear();
    });
    try {
      // 章节列表只在首次进入时取一次；换章时服务端进度已不适用，直接从第一页开始。
      final info = _chapters.isEmpty
          ? await ref.read(readerComicInfoProvider(widget.bookId).future)
          : null;
      if (!mounted || version != _requestVersion) return;
      final chapters = info?.chapters ?? _chapters;

      var index = chapters.indexWhere((item) => item.sortNum == _sortNum);
      if (index < 0 && _sortNum >= 1 && _sortNum <= chapters.length) {
        index = _sortNum - 1;
      }
      if (index < 0) throw const ApiError('章节不存在。', ApiErrorCategory.server);
      final chapter = chapters[index];

      final target = _resolveInitialPage(chapter, info?.readPosition);
      var total = chapter.pageCount;
      var skip = getComicPageBatchStart(target, math.max(total, 1), _batchSize);
      var content = await _api.getComicContent(
        chapterId: chapter.id,
        skip: skip,
        take: _batchSize,
      );
      if (!mounted || version != _requestVersion) return;

      // 目录里的页数偶尔滞后，以正文返回的 total 为准并按需重取。
      if (content.chapter.total != total) {
        total = content.chapter.total;
        final corrected = getComicPageBatchStart(
          target,
          math.max(total, 1),
          _batchSize,
        );
        if (corrected != skip) {
          skip = corrected;
          content = await _api.getComicContent(
            chapterId: chapter.id,
            skip: skip,
            take: _batchSize,
          );
          if (!mounted || version != _requestVersion) return;
        }
      }

      final page = total == 0 ? 0 : target.clamp(0, total - 1);
      setState(() {
        _chapters = chapters;
        _chapterIndex = index;
        _chapter = chapter;
        _slots = mergeComicPageBatch(
          createComicPageSlots(total),
          content.chapter.skip,
          content.chapter.images,
        );
        _page = page;
        _direction = 1;
        _loading = false;
      });
      _resetControllers(page);
      _stage(page);
      await _positions.commit(
        ReaderRestorePosition(chapterId: chapter.id, position: '${page + 1}'),
      );
      unawaited(_prefetch());
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error is ApiError ? error.message : '漫画加载失败，请稍后重试。';
        _loading = false;
      });
    }
  }

  int _resolveInitialPage(
    ComicChapterSummary chapter,
    BookReadPosition? server,
  ) {
    final cached = ReadPositionCache.read(widget.bookId);
    final restore = resolveReaderRestorePosition(
      chapter.id,
      server == null
          ? null
          : ReaderRestorePosition(
              chapterId: server.chapterId,
              position: server.position,
            ),
      cached == null
          ? null
          : CachedReaderRestorePosition(
              chapterId: cached.chapterId,
              position: cached.position,
            ),
    );
    final saved = int.tryParse(restore?.position ?? '') ?? 1;
    return resolveReaderInitialIndex(
      ReaderOpenPosition.saved,
      saved - 1,
      chapter.pageCount,
    );
  }

  /// 旧控制器要等这一帧的 widget 换掉之后再释放，否则仍挂在树上的列表会用到已释放的控制器。
  void _resetControllers(int page) {
    final previousPage = _pageController;
    final previousScroll = _scrollController?..removeListener(_onScroll);
    _pageController = PageController(initialPage: page);
    _scrollController = ScrollController(
      initialScrollOffset: _offsetForPage(page),
    )..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousPage?.dispose();
      previousScroll?.dispose();
    });
  }

  /// 切换阅读模式后，把新挂载的列表滚回当前页。
  void _syncToPage() {
    if (!mounted) return;
    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.jumpToPage(_page);
      return;
    }
    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) return;
    scrollController.jumpTo(
      _offsetForPage(_page)
          .clamp(0.0, scrollController.position.maxScrollExtent),
    );
  }

  Future<void> _ensureBatch(int pageIndex, {bool retry = false}) async {
    final chapter = _chapter;
    if (chapter == null || _slots.isEmpty) return;
    if (pageIndex < 0 || pageIndex >= _slots.length) return;
    final skip = getComicPageBatchStart(pageIndex, _slots.length, _batchSize);
    if (_loadingBatches.contains(skip)) return;
    if (_failedBatches.contains(skip) && !retry) return;
    final end = math.min(skip + _batchSize, _slots.length);
    var missing = false;
    for (var index = skip; index < end; index++) {
      if (_slots[index].image == null) {
        missing = true;
        break;
      }
    }
    if (!missing) return;

    final version = _requestVersion;
    _loadingBatches.add(skip);
    _failedBatches.remove(skip);
    try {
      final content = await _api.getComicContent(
        chapterId: chapter.id,
        skip: skip,
        take: _batchSize,
        priority: RequestPriority.preload,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _slots = mergeComicPageBatch(
          _slots,
          content.chapter.skip,
          content.chapter.images,
        );
      });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() => _failedBatches.add(skip));
    } finally {
      _loadingBatches.remove(skip);
    }
  }

  /// 当前页两侧优先取图，再沿阅读方向预取，翻页时几乎不会看到空白。
  Future<void> _prefetch() async {
    final plan = createComicPrefetchPlan(_page, _slots.length, _direction);
    for (final index in plan) {
      await _ensureBatch(index);
    }
    if (!mounted) return;
    for (final index in plan) {
      final image = _slots[index].image;
      if (image == null) continue;
      // 必须和 `BookImage` 落到同一个尺寸档，否则 URL 与缓存键都对不上，
      // 预取的字节一个字节都命不中。
      final url = sizedImageUrl(
        image.url,
        logicalHeight: _pageHeight(index),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(
            url,
            cacheKey: BookImage.cacheKeyFor(url),
            cacheManager: appImageCacheManager,
          ),
          context,
        ).catchError((Object _) {}),
      );
    }
  }

  void _stage(int page) {
    final chapter = _chapter;
    if (chapter == null) return;
    final position = ReaderRestorePosition(
      chapterId: chapter.id,
      position: '${page + 1}',
    );
    // 立刻写进程内缓存，详情页/书架马上能看到最新进度。
    ReadPositionCache.stage(
      widget.bookId,
      BookReadPosition(
        chapterId: position.chapterId,
        position: position.position,
        readAt: DateTime.now(),
      ),
    );
    _positions.schedule(position);
  }

  void _onPageChanged(int page) {
    if (page == _page) return;
    setState(() {
      _direction = page > _page ? 1 : -1;
      _page = page;
    });
    _stage(page);
    unawaited(_prefetch());
  }

  double _aspect(int _) => _unknownAspect;

  double _continuousWidth() {
    final size = MediaQuery.sizeOf(context);
    return getContinuousComicContentWidth(size.width, size.height);
  }

  /// 当前模式下整页的宽度。翻页模式铺满屏宽，连续模式按内容宽收窄。
  double _pageWidth() => _mode == ReaderViewMode.paged
      ? MediaQuery.sizeOf(context).width
      : _continuousWidth();

  /// 整页高度。展示与预取都走这里，尺寸档才不会分叉。
  double _pageHeight(int index) => _pageWidth() * _aspect(index);

  double _offsetForPage(int page) {
    if (!mounted) return 0;
    final width = _continuousWidth();
    var offset = 0.0;
    for (var index = 0; index < page && index < _slots.length; index++) {
      offset += width * _aspect(index);
    }
    return offset;
  }

  void _onScroll() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients || _slots.isEmpty) return;
    final width = _continuousWidth();
    var offset = controller.offset + 1;
    var page = 0;
    for (var index = 0; index < _slots.length; index++) {
      final height = width * _aspect(index);
      if (offset < height) {
        page = index;
        break;
      }
      offset -= height;
      page = index;
    }
    if (page == _page) return;
    setState(() {
      _direction = page > _page ? 1 : -1;
      _page = page;
    });
    _stage(page);
    unawaited(_prefetch());
  }

  void _turn(int delta) {
    final target = (_page + delta)
        .clamp(0, math.max(0, _slots.length - 1))
        .toInt();
    if (target == _page) return;
    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.jumpToPage(target);
      return;
    }
    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) return;
    final viewport = scrollController.position.viewportDimension;
    scrollController.jumpTo(
      (scrollController.offset + delta * viewport).clamp(
        0.0,
        scrollController.position.maxScrollExtent,
      ),
    );
  }

  Future<void> _openChapterIndex(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    await _commitPosition();
    if (!mounted) return;
    setState(() => _sortNum = _chapters[index].sortNum);
    await _loadChapter();
  }

  Future<void> _commitPosition() async {
    final chapter = _chapter;
    if (chapter == null) return;
    await _positions.commit(
      ReaderRestorePosition(chapterId: chapter.id, position: '${_page + 1}'),
    );
  }

  Future<void> _openChapterSheet() async {
    final selection = await showReaderChapterSheet(
      context,
      bookId: widget.bookId,
      currentSortNum: _sortNum,
      comic: true,
    );
    if (selection == null) return;
    final index = _chapters.indexWhere(
      (item) => item.sortNum == selection.sortNum,
    );
    await _openChapterIndex(index < 0 ? 0 : index);
  }

  void _onTapZone(double position, double extent, bool reversed) {
    final zone = resolveComicTapDirection(position, extent);
    if (zone == 0) {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }
    _turn(reversed ? -zone : zone);
  }

  Widget _pageContent(int index, double width, double height) {
    final slot = _slots[index];
    final image = slot.image;
    if (image == null) {
      final skip = getComicPageBatchStart(index, _slots.length, _batchSize);
      if (_failedBatches.contains(skip)) {
        return ComicRetryTile(
          width: width,
          height: height,
          onRetry: () => unawaited(_ensureBatch(index, retry: true)),
        );
      }
      unawaited(_ensureBatch(index));
      return SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
    }
    return ContentImage(
      url: image.url,
      width: width,
      height: height,
      blurHash: image.placeholder,
      fadeInDuration: const Duration(milliseconds: 80),
      errorBuilder: (context, retry) =>
          ComicRetryTile(width: width, height: height, onRetry: retry),
    );
  }

  Widget _pagedView(bool reversed) {
    final size = MediaQuery.sizeOf(context);
    return PhotoViewGallery.builder(
      itemCount: _slots.length,
      pageController: _pageController,
      reverse: reversed,
      onPageChanged: _onPageChanged,
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      builder: (context, index) => PhotoViewGalleryPageOptions.customChild(
        childSize: Size(size.width, size.width * _aspect(index)),
        minScale: PhotoViewComputedScale.contained,
        initialScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.contained * 6,
        onTapUp: (context, details, _) =>
            _onTapZone(details.globalPosition.dx, size.width, reversed),
        child: _pageContent(index, size.width, size.width * _aspect(index)),
      ),
    );
  }

  Widget _continuousView() {
    final width = _continuousWidth();
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) =>
            _onTapZone(details.localPosition.dy, constraints.maxHeight, false),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _slots.length,
          itemExtentBuilder: (index, _) => width * _aspect(index),
          itemBuilder: (context, index) => Center(
            child: SizedBox(
              width: width,
              child: _pageContent(index, width, width * _aspect(index)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark && settings.oledBlack
        ? Colors.black
        : colors.surface;
    final foreground = dark && settings.oledBlack
        ? Colors.white
        : colors.onSurface;
    final paged = settings.readerViewMode == ReaderViewMode.paged;
    // 切换阅读模式时保留当前页码。
    if (_mode != settings.readerViewMode) {
      _mode = settings.readerViewMode;
      if (!_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncToPage());
      }
    }

    final Widget body;
    if (_error != null) {
      body = Center(
        child: ErrorStateView(
          message: _error!,
          onRetry: () => unawaited(_loadChapter()),
        ),
      );
    } else if (_loading || _chapter == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_slots.isEmpty) {
      body = const Center(
        child: EmptyStateView(icon: Icons.image_outlined, title: '本章暂无页面'),
      );
    } else {
      body = paged
          ? _pagedView(settings.comicPagedDirection == ComicPagedDirection.rtl)
          : _continuousView();
    }

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          if (_slots.isNotEmpty)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        '${_page + 1} / ${_slots.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ReaderChrome(
            visible: _chromeVisible,
            title: _chapter?.title.isNotEmpty == true
                ? _chapter!.title
                : '漫画阅读器',
            backgroundColor: background,
            foregroundColor: foreground,
            currentChapter: _chapterIndex + 1,
            totalChapters: _chapters.length,
            progress: _slots.isEmpty ? null : (_page + 1) / _slots.length,
            onOpenChapters: () => unawaited(_openChapterSheet()),
            onOpenSettings: () => unawaited(showReaderSettingsSheet(context)),
            onDismiss: () => setState(() => _chromeVisible = false),
            onPreviousChapter: _chapterIndex > 0
                ? () => unawaited(_openChapterIndex(_chapterIndex - 1))
                : null,
            onNextChapter: _chapterIndex < _chapters.length - 1
                ? () => unawaited(_openChapterIndex(_chapterIndex + 1))
                : null,
          ),
        ],
      ),
    );
  }
}
