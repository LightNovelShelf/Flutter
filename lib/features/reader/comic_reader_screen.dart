import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../core/platform/reader_immersive_mode.dart';
import '../../core/platform/reader_volume_keys.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/image_cache.dart';
import '../../shared/image_sizing.dart';
import '../../shared/widgets/book_image.dart';
import '../../shared/widgets/image_preview.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_comic_paging.dart';
import 'reader_open_position.dart';
import 'reader_page_turn.dart';
import 'reader_pagination.dart';
import 'reader_position.dart';
import 'reader_progress_controller.dart';
import 'reader_providers.dart';
import 'widgets/comic_retry_tile.dart';
import 'widgets/reader_chapter_sheet.dart';
import 'widgets/reader_chrome.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/reader_shell.dart';
import 'widgets/reader_status_pills.dart';
import 'widgets/reader_tap_zone.dart';
import 'widgets/reader_theme.dart';

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

class _ComicReaderScreenState extends ConsumerState<ComicReaderScreen>
    with ReaderLoadState<ComicReaderScreen> {
  static const int _batchSize = 12;

  /// 尺寸未知时先按常见竖版单页占位。
  static const double _unknownAspect = 1.5;

  late final ApiClient _api;
  late final ReaderProgressController _progress;

  late int _sortNum;
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(false);

  List<ComicChapterSummary> _chapters = const <ComicChapterSummary>[];

  /// 章节标题表只在 `_chapters` 换了之后重建，工具栏每帧都要读它。
  List<String> _chapterTitles = const <String>[];
  int _chapterIndex = 0;
  ComicChapterSummary? _chapter;
  List<ComicPageSlot> _slots = const <ComicPageSlot>[];

  /// 前 i 页高宽比之和，乘上页宽就是第 i 页的顶部偏移。页宽变了不用重算，只有 `_slots` 变才重建。
  List<double> _aspectPrefix = const <double>[0];

  /// 双页模式下的分屏表：每一屏一到两页。关掉或屏幕放不下时为空。
  List<List<int>> _spreads = const <List<int>>[];

  /// 每页落在第几屏，与 [_spreads] 同批重建。
  List<int> _spreadOfPage = const <int>[];
  bool _dual = false;
  bool _offsetFirstPage = false;

  /// 当前页只驱动页码指示器和工具栏，连续模式下滚动换页不重建整屏。
  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);
  int get _page => _pageNotifier.value;
  int _direction = 1;

  final Set<int> _loadingBatches = <int>{};
  final Set<int> _failedBatches = <int>{};

  /// 构建期发现缺图的批次先攒着，帧末统一取。
  final Set<int> _pendingBatches = <int>{};
  bool _batchFlushScheduled = false;

  Timer? _prefetchTimer;

  /// 已提交 precache 的缓存键，快速滚动时同一张图不重复排解码任务。
  final Set<String> _precachedKeys = <String>{};

  /// MediaQuery 只在 `didChangeDependencies` 里读一次，滚动回调不逐帧查 InheritedModel。
  Size _screenSize = Size.zero;
  double _devicePixelRatio = 1;
  double _continuousPageWidth = 0;

  PageController? _pageController;
  ScrollController? _scrollController;
  ReaderViewMode? _mode;

  @override
  void initState() {
    super.initState();
    _sortNum = widget.sortNum;
    _api = ref.read(apiClientProvider);
    _progress = ReaderProgressController(api: _api, bookId: widget.bookId);
    unawaited(_loadChapter());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final size = MediaQuery.sizeOf(context);
    if (size != _screenSize) {
      _screenSize = size;
      _continuousPageWidth = getContinuousComicContentWidth(
        size.width,
        size.height,
      );
    }
    // 旋转屏幕会让分屏在开合之间切换，当前页所在的那一屏要重新对准。
    final reader = ref.read(appSettingsProvider).comicReader;
    if (_syncDual(reader.dualPageEnabled, reader.dualPageOffsetEnabled) &&
        !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToPage());
    }
  }

  /// 按设置与屏幕尺寸决定分不分屏，变了就重建分屏表并返回 true。
  bool _syncDual(bool enabled, bool offsetFirstPage) {
    final dual = readerFixedLayoutSpread(
      dualPage: enabled,
      width: _screenSize.width,
      height: _screenSize.height,
    );
    final offset = dual && offsetFirstPage;
    if (dual == _dual && offset == _offsetFirstPage) return false;
    _dual = dual;
    _offsetFirstPage = offset;
    _rebuildSpreads();
    return true;
  }

  /// 分屏只在翻页模式下作数，连续模式仍是一页接一页。
  bool get _dualPaged =>
      _dual && _mode == ReaderViewMode.paged && _spreads.isNotEmpty;

  /// 第 [page] 页在第几屏；不分屏时就是页码本身。
  int _spreadIndexOf(int page) =>
      page >= 0 && page < _spreadOfPage.length ? _spreadOfPage[page] : page;

  /// 第 [page] 页所在屏的屏首。当前页一律按屏首记，页码才跟翻页条上的位置对得上。
  int _spreadHeadOf(int page) {
    final spread = _spreadIndexOf(page);
    return spread >= 0 && spread < _spreads.length
        ? _spreads[spread].first
        : page;
  }

  void _rebuildSpreads() {
    if (!_dual || _slots.isEmpty) {
      _spreads = const <List<int>>[];
      _spreadOfPage = const <int>[];
      return;
    }
    _spreads = createComicSpreads(<double>[
      for (var index = 0; index < _slots.length; index++) _aspect(index),
    ], offsetFirstPage: _offsetFirstPage);
    _spreadOfPage = createComicSpreadIndex(_spreads, _slots.length);
  }

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    unawaited(_progress.dispose());
    _pageController?.dispose();
    _scrollController?.dispose();
    _pageNotifier.dispose();
    _chromeVisible.dispose();
    super.dispose();
  }

  Future<void> _loadChapter() async {
    final version = beginRequest();
    setState(() {
      loading = true;
      loadError = null;
      _loadingBatches.clear();
      _failedBatches.clear();
      _pendingBatches.clear();
      _precachedKeys.clear();
    });
    try {
      // 章节列表只在首次进入时取一次，换章时服务端进度不适用，从第一页开始。
      final info = _chapters.isEmpty
          ? await ref.read(readerComicInfoProvider(widget.bookId).future)
          : null;
      if (isStale(version)) return;
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
      if (isStale(version)) return;

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
          if (isStale(version)) return;
        }
      }

      final page = total == 0 ? 0 : target.clamp(0, total - 1);
      _pageNotifier.value = page;
      setState(() {
        _chapters = chapters;
        _chapterTitles = <String>[
          for (final chapter in chapters) chapter.title,
        ];
        _chapterIndex = index;
        _chapter = chapter;
        _setSlots(
          mergeComicPageBatch(
            createComicPageSlots(total),
            content.chapter.skip,
            content.chapter.images,
          ),
        );
        _direction = 1;
        loading = false;
      });
      // 分屏表随 _setSlots 建好，落位的页要退回所在屏的屏首。
      final aligned = _dualPaged ? _spreadHeadOf(page) : page;
      _pageNotifier.value = aligned;
      _resetControllers(aligned);
      _stage(aligned);
      await _progress.commit(chapter.id, '${aligned + 1}');
      _schedulePrefetch();
    } catch (failure) {
      if (isStale(version)) return;
      setState(() {
        loadError = failure is ApiError ? failure.message : '漫画加载失败，请稍后重试。';
        loading = false;
      });
    }
  }

  int _resolveInitialPage(
    ComicChapterSummary chapter,
    BookReadPosition? server,
  ) {
    final restore = resolveReaderRestore(
      bookId: widget.bookId,
      chapterId: chapter.id,
      server: server,
    );
    final saved = int.tryParse(restore?.position ?? '') ?? 1;
    return resolveReaderInitialIndex(
      ReaderOpenPosition.saved,
      saved - 1,
      chapter.pageCount,
    );
  }

  /// 旧控制器在下一帧释放，否则仍挂在树上的列表会用到已释放的控制器。
  void _resetControllers(int page) {
    final previousPage = _pageController;
    final previousScroll = _scrollController?..removeListener(_onScroll);
    _pageController = PageController(
      initialPage: _dualPaged ? _spreadIndexOf(page) : page,
    );
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
      // 配对变了会把当前页挪到别人那一屏的中间，先退回屏首再对准。
      if (_dualPaged) _onPageChanged(_spreadHeadOf(_page));
      pageController.jumpToPage(_dualPaged ? _spreadIndexOf(_page) : _page);
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

    final version = requestVersion;
    _loadingBatches.add(skip);
    _failedBatches.remove(skip);
    // 声明成 final 而不是 `double?`：只有 try 正常走完才会落到下面的对位，
    // 哪天 catch 少写一个 return，这里会直接编译不过而不是悄悄传个 null。
    final double anchor;
    try {
      final content = await _api.getComicContent(
        chapterId: chapter.id,
        skip: skip,
        take: _batchSize,
        priority: RequestPriority.preload,
      );
      if (isStale(version)) return;
      // 新一批图带来真实比例，之前按未知比例占位的页高会变，先记下当前页起点再补回偏移。
      anchor = _offsetForPage(_page);
      setState(() {
        _setSlots(
          mergeComicPageBatch(
            _slots,
            content.chapter.skip,
            content.chapter.images,
          ),
        );
      });
    } catch (_) {
      if (isStale(version)) return;
      setState(() => _failedBatches.add(skip));
      return;
    } finally {
      _loadingBatches.remove(skip);
    }
    // 重新对位放在 try 之外：这里抛的是布局/下标问题，不该被记成这一批图加载失败，
    // 那会给无关的页画上重试块并锁住重新取图。
    _restoreAnchor(anchor);
    // 配对可能被新到的宽图错开一位，当前页所在的那一屏要重新对准。
    if (_dualPaged) _syncToPage();
  }

  /// 换页节流：快速滚动会连着跨很多页，只对停住的位置排预取，避免成串解码任务抢 UI/raster。
  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(_prefetch()),
    );
  }

  /// 当前页两侧优先取图，再沿阅读方向预取。
  Future<void> _prefetch() async {
    final plan = createComicPrefetchPlan(_page, _slots.length, _direction);
    for (final index in plan) {
      await _ensureBatch(index);
    }
    if (!mounted) return;
    final devicePixelRatio = _devicePixelRatio;
    for (final index in plan) {
      // 上面的等待期间可能换了章，槽位数会变。
      if (index >= _slots.length) continue;
      final image = _slots[index].image;
      if (image == null) continue;
      // 必须和 `BookImage` 落到同一个尺寸档，否则 URL 与缓存键对不上，预取不会命中。
      final url = sizedImageUrl(
        image.url,
        logicalHeight: _pageHeight(index),
        devicePixelRatio: devicePixelRatio,
      );
      final cacheKey = BookImage.cacheKeyFor(url);
      if (!_precachedKeys.add(cacheKey)) continue;
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(
            url,
            cacheKey: cacheKey,
            cacheManager: appImageCacheManager,
          ),
          context,
        ).catchError((Object _) {
          // 预取失败的键放回去，下次经过这页还能再试。
          _precachedKeys.remove(cacheKey);
        }),
      );
    }
  }

  void _stage(int page) {
    final chapter = _chapter;
    if (chapter == null) return;
    _progress.stage(chapter.id, '${page + 1}');
  }

  void _onPageChanged(int page) {
    if (page == _page) return;
    _direction = page > _page ? 1 : -1;
    _pageNotifier.value = page;
    _stage(page);
    _schedulePrefetch();
  }

  /// 整页高宽比。地址上带 `size` 就用真实比例，横跨两页的宽图才不会被塞进竖版版面。
  double _aspect(int index) {
    if (index < 0 || index >= _slots.length) return _unknownAspect;
    return _slots[index].image?.aspect ?? _unknownAspect;
  }

  /// 换 `_slots` 必须走这里，页高前缀和要跟着重建。
  void _setSlots(List<ComicPageSlot> slots) {
    _slots = slots;
    final prefix = List<double>.filled(slots.length + 1, 0);
    var sum = 0.0;
    for (var index = 0; index < slots.length; index++) {
      sum += slots[index].image?.aspect ?? _unknownAspect;
      prefix[index + 1] = sum;
    }
    _aspectPrefix = prefix;
    // 新一批图带来真实比例，宽图会改变配对，分屏表跟着重建。
    _rebuildSpreads();
  }

  /// 整页高度，展示与预取共用同一个算式，避免尺寸档分叉。翻页模式铺满屏宽，连续模式按内容宽收窄。
  double _pageHeight(int index) => _mode == ReaderViewMode.paged
      ? _pagedPageWidth(index) * _aspect(index)
      : _continuousPageExtent(index);

  /// 翻页模式下这一页占多宽：分屏时竖版页只占半屏，横跨两页的宽图仍铺满。
  double _pagedPageWidth(int index) => _dualPaged && _aspect(index) >= 1
      ? _screenSize.width / 2
      : _screenSize.width;

  double _offsetForPage(int page) =>
      _continuousPageWidth * _aspectPrefix[page.clamp(0, _slots.length)];

  /// 连续模式下第 index 页的高度，和 `_offsetForPage` 共用前缀和，两者不会算出不一致的版面。
  double _continuousPageExtent(int index) =>
      _continuousPageWidth * (_aspectPrefix[index + 1] - _aspectPrefix[index]);

  /// 偏移落在哪一页。判定点取 offset + 1，正好停在页边界时才不会判回上一页。
  int _pageAtOffset(double offset) {
    if (_continuousPageWidth <= 0 || _slots.isEmpty) return 0;
    final target = (offset + 1) / _continuousPageWidth;
    var low = 0;
    var high = _slots.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_aspectPrefix[mid] <= target) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// 页高变化后把当前页钉回原位。连续模式按累计页高定位，前面任何一页变高变矮都会整体平移。
  ///
  /// 同帧内改 offset，布局用新页高排一次，看不到中间态；上界不夹，越界由随后的布局纠正。
  void _restoreAnchor(double anchor) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final delta = _offsetForPage(_page) - anchor;
    if (delta == 0) return;
    controller.jumpTo(math.max(0, controller.offset + delta));
  }

  void _onScroll() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients || _slots.isEmpty) return;
    final page = _pageAtOffset(controller.offset);
    if (page == _page) return;
    _direction = page > _page ? 1 : -1;
    _pageNotifier.value = page;
    _stage(page);
    _schedulePrefetch();
  }

  void _turn(int delta) {
    if (loading || loadError != null || _slots.isEmpty) return;
    final pageController = _pageController;
    if (_dualPaged && pageController != null && pageController.hasClients) {
      final current = _spreadIndexOf(_page);
      final target = (current + delta).clamp(0, _spreads.length - 1).toInt();
      if (target == current) return;
      turnReaderPage(
        pageController,
        target,
        ref.read(appSettingsProvider).comicReader.pageTurnAnimation,
      );
      return;
    }
    final target = (_page + delta)
        .clamp(0, math.max(0, _slots.length - 1))
        .toInt();
    if (target == _page) return;
    if (pageController != null && pageController.hasClients) {
      turnReaderPage(
        pageController,
        target,
        ref.read(appSettingsProvider).comicReader.pageTurnAnimation,
      );
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
    await _progress.commit(chapter.id, '${_page + 1}');
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

  void _toggleChrome() => _chromeVisible.value = !_chromeVisible.value;

  /// 构建期只登记缺图的批次，帧末再发请求：build 里不能有网络副作用和 setState。
  void _requestBatch(int skip) {
    if (_loadingBatches.contains(skip)) return;
    if (!_pendingBatches.add(skip) || _batchFlushScheduled) return;
    _batchFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _batchFlushScheduled = false;
      final pending = List<int>.of(_pendingBatches);
      _pendingBatches.clear();
      if (!mounted) return;
      for (final index in pending) {
        unawaited(_ensureBatch(index));
      }
    });
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
      _requestBatch(skip);
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

  /// 一屏的自然尺寸。宽图独占整屏，落单的竖版页仍按半屏宽算，翻页时页面大小不跳。
  Size _spreadSize(List<int> pages, double width) {
    final half = width / 2;
    var height = 0.0;
    for (final page in pages) {
      final aspect = _aspect(page);
      final pageWidth = aspect < 1 ? width : half;
      height = math.max(height, pageWidth * aspect);
    }
    return Size(width, height);
  }

  /// 一屏的正文：两页并排，右起时右边那页在前。
  Widget _spreadContent(List<int> pages, Size size, bool reversed) {
    final half = size.width / 2;
    Widget page(int index) {
      final aspect = _aspect(index);
      final pageWidth = aspect < 1 ? size.width : half;
      return SizedBox(
        width: pageWidth,
        height: size.height,
        // 两页按中线对齐，高度不同也不会一上一下。
        child: Center(
          child: _pageContent(index, pageWidth, pageWidth * aspect),
        ),
      );
    }

    return SizedBox(
      width: size.width,
      height: size.height,
      child: pages.length == 1
          ? Center(child: page(pages.first))
          : Row(
              textDirection: reversed ? TextDirection.rtl : TextDirection.ltr,
              children: <Widget>[for (final index in pages) page(index)],
            ),
    );
  }

  Widget _pagedView(bool reversed) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final spreads = _dualPaged ? _spreads : null;
      final gallery = PhotoViewGallery.builder(
        itemCount: spreads?.length ?? _slots.length,
        pageController: _pageController,
        reverse: reversed,
        // 当前页按屏首算，与小说阅读器一致：翻页条上的位置就是这一屏最前面那一页。
        // 读实时的 _spreads：jumpToPage 会同步派发滚动通知，而这一跳往往就发生在新一批
        // 图刚改过配对、PhotoViewGallery 还没重建的时候，捕获的旧表会错位甚至越界。
        onPageChanged: spreads == null
            ? _onPageChanged
            : (index) => _onPageChanged(
                index >= 0 && index < _spreads.length
                    ? _spreads[index].first
                    : index,
              ),
        backgroundDecoration: const BoxDecoration(color: Colors.transparent),
        builder: (context, index) {
          if (spreads == null) {
            return PhotoViewGalleryPageOptions.customChild(
              childSize: Size(size.width, size.width * _aspect(index)),
              minScale: PhotoViewComputedScale.contained,
              initialScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.contained * 6,
              child: _pageContent(
                index,
                size.width,
                size.width * _aspect(index),
              ),
            );
          }
          final pages = spreads[index];
          final spreadSize = _spreadSize(pages, size.width);
          return PhotoViewGalleryPageOptions.customChild(
            childSize: spreadSize,
            minScale: PhotoViewComputedScale.contained,
            initialScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.contained * 6,
            child: _spreadContent(pages, spreadSize, reversed),
          );
        },
      );
      // PhotoView 会先消费子树里的点按，热区必须铺在它上面。
      return Stack(
        children: <Widget>[
          Positioned.fill(child: gallery),
          Positioned.fill(
            child: ReaderTapZoneLayer(
              reversed: reversed,
              onPrevious: () => _turn(-1),
              onNext: () => _turn(1),
              onToggleChrome: _toggleChrome,
            ),
          ),
        ],
      );
    },
  );

  Widget _continuousView() {
    final width = _continuousPageWidth;
    return ReaderTapZoneLayer(
      axis: Axis.vertical,
      onPrevious: () => _turn(-1),
      onNext: () => _turn(1),
      onToggleChrome: _toggleChrome,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _slots.length,
        itemExtentBuilder: (index, _) => _continuousPageExtent(index),
        itemBuilder: (context, index) => Center(
          child: SizedBox(
            width: width,
            child: _pageContent(index, width, _continuousPageExtent(index)),
          ),
        ),
      ),
    );
  }

  Widget _chrome({
    required bool visible,
    required int page,
    required Color background,
    required Color foreground,
    required bool themeLocked,
  }) => ReaderChrome(
    visible: visible,
    title: _chapter?.title.isNotEmpty == true ? _chapter!.title : '漫画阅读器',
    backgroundColor: background,
    foregroundColor: foreground,
    currentChapter: _chapterIndex + 1,
    totalChapters: _chapters.length,
    chapterTitles: _chapterTitles,
    progress: _slots.isEmpty ? null : (page + 1) / _slots.length,
    onOpenChapters: () => unawaited(_openChapterSheet()),
    nightMode: Theme.of(context).brightness == Brightness.dark,
    onToggleNightMode: themeLocked
        ? null
        : () => toggleReaderNightMode(context, ref, BookType.comic),
    onOpenSettings: () =>
        unawaited(showReaderSettingsSheet(context, BookType.comic)),
    onDismiss: () => _chromeVisible.value = false,
    onPreviousChapter: _chapterIndex > 0
        ? () => unawaited(_openChapterIndex(_chapterIndex - 1))
        : null,
    onNextChapter: _chapterIndex < _chapters.length - 1
        ? () => unawaited(_openChapterIndex(_chapterIndex + 1))
        : null,
    onChapterSelected: (chapter) => unawaited(_openChapterIndex(chapter - 1)),
  );

  @override
  Widget build(BuildContext context) {
    // 只取实际用到的设置，阅读设置面板拖动滑块写入无关字段时不重建整棵树。
    final (
      :oledBlack,
      :backgroundMode,
      :backgroundColorValue,
      :viewMode,
      :pagedDirection,
      :volumeKeyPagingEnabled,
      :immersiveEnabled,
      :dualPageEnabled,
      :dualPageOffsetEnabled,
      :statusPillsEnabled,
    ) = ref.watch(
      appSettingsProvider.select(
        (settings) => (
          oledBlack: settings.oledBlack,
          backgroundMode: settings.comicReader.backgroundMode,
          backgroundColorValue: settings.comicReader.backgroundColorValue,
          viewMode: settings.comicReader.viewMode,
          pagedDirection: settings.comicPagedDirection,
          volumeKeyPagingEnabled: settings.comicReader.volumeKeyPagingEnabled,
          immersiveEnabled: settings.comicReader.immersiveEnabled,
          dualPageEnabled: settings.comicReader.dualPageEnabled,
          dualPageOffsetEnabled: settings.comicReader.dualPageOffsetEnabled,
          statusPillsEnabled: settings.comicReader.statusPillsEnabled,
        ),
      ),
    );
    final (:background, :foreground) = readerSurfaceColors(
      context,
      mode: backgroundMode,
      customColorValue: backgroundColorValue,
      oledBlack: oledBlack,
    );
    // 阅读模式与分屏都会换掉翻页条的页序，落定后要把当前页重新对准。
    // 用 `|` 不用 `||`：`_syncDual` 要在这一帧就把分屏表建好，供下面的 body 取用，
    // 短路掉就会拿旧表画一帧。
    final relaid =
        _syncDual(dualPageEnabled, dualPageOffsetEnabled) | (_mode != viewMode);
    _mode = viewMode;
    if (relaid && !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToPage());
    }

    final paged = viewMode == ReaderViewMode.paged;
    final pills = paged && statusPillsEnabled;

    final Widget body;
    if (_chapter == null) {
      body = const SizedBox.shrink();
    } else if (_slots.isEmpty) {
      body = const Center(
        child: EmptyStateView(icon: Icons.image_outlined, title: '本章暂无页面'),
      );
    } else {
      body = paged
          ? _pagedView(pagedDirection == ComicPagedDirection.rtl)
          : _continuousView();
    }

    final shell = ReaderShell(
      background: background,
      paperTexture: backgroundMode == ReaderBackgroundMode.paper,
      loading: loading || _chapter == null,
      error: loadError,
      onRetry: () => unawaited(_loadChapter()),
      body: SafeArea(
        left: false,
        right: false,
        bottom: paged,
        child: paged
            ? Padding(
                padding: EdgeInsets.only(top: 12, bottom: pills ? 56 : 12),
                child: body,
              )
            : body,
      ),
      overlay: _slots.isEmpty || !pills
          ? null
          : Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _chromeVisible,
                    builder: (context, visible, _) =>
                        ValueListenableBuilder<int>(
                          valueListenable: _pageNotifier,
                          builder: (context, page, _) => ReaderStatusPills(
                            visible: !visible,
                            foregroundColor: foreground,
                            currentChapter: _chapterIndex + 1,
                            totalChapters: _chapters.length,
                            currentPage: page + 1,
                            totalPages: _slots.length,
                          ),
                        ),
                  ),
                ),
              ),
            ),
      chrome: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, _) => ValueListenableBuilder<int>(
          valueListenable: _pageNotifier,
          builder: (context, page, _) => _chrome(
            visible: visible,
            page: page,
            background: background,
            foreground: foreground,
            themeLocked: backgroundMode == ReaderBackgroundMode.custom,
          ),
        ),
      ),
    );
    return ReaderImmersiveMode(
      enabled: immersiveEnabled,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        child: shell,
        builder: (context, chromeVisible, child) => ReaderVolumeKeyListener(
          enabled: volumeKeyPagingEnabled && !chromeVisible,
          onPrevious: () => _turn(-1),
          onNext: () => _turn(1),
          child: child!,
        ),
      ),
    );
  }
}
