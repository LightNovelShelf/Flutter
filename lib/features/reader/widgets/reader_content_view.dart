import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/html/reader_content_style.dart';
import '../../../shared/widgets/reader_html_block.dart';
import '../reader_block_markup.dart';
import '../reader_html_blocks.dart';
import '../reader_pagination.dart';
import '../reader_position.dart';
import 'reader_measure_box.dart';
import 'reader_page_body.dart';
import 'reader_tap_zone.dart';

/// 一章正文及其排版参数。正文字形逐章混淆，字体各章不同，所以样式随章走。
class ReaderChapterContent {
  const ReaderChapterContent({
    required this.sortNum,
    required this.blocks,
    required this.style,
  });

  final int sortNum;
  final List<NovelReaderBlock> blocks;
  final ReaderContentStyle style;
}

/// 正文位置上报。`page`/`pages` 从 1 开始，滚动模式恒为 0。
/// 上报发生在上层切章之前，因此自带 [sortNum]。
class ReaderContentPosition {
  const ReaderContentPosition({
    required this.sortNum,
    required this.locator,
    required this.progression,
    required this.page,
    required this.pages,
  });

  final int sortNum;
  final String locator;
  final double progression;
  final int page;
  final int pages;
}

/// 从阅读器外部触发正文前后翻页；未挂载或正文尚未就绪时操作会被忽略。
class ReaderContentController {
  _ReaderContentViewState? _state;

  void previousPage() => _state?._turnFromController(false);

  void nextPage() => _state?._turnFromController(true);

  void _attach(_ReaderContentViewState state) => _state = state;

  void _detach(_ReaderContentViewState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// 原生正文视图。
///
/// 正文用 `HtmlWidget` 渲染，翻页与定位在 Flutter 侧完成：先把整章排进零尺寸的测量层，
/// 读出每个块的纵向区间与每行行顶，再按视口高度切页；翻页模式的每一页只摆落在该页区间的块
/// 并裁掉溢出。排版、视口、图片尺寸变化会重新测量，并把阅读位置定回当前 locator。
///
/// [previous]/[next] 各有自己的测量层，测完后接在当前章两端组成翻页条，跨章翻页即走到条上的
/// 下一页，落定后由 [onChapterChanged] 通知上层平移窗口。相邻章未备好时越界翻页走 [onBoundary]。
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.chapter,
    required this.previous,
    required this.next,
    required this.paged,
    required this.padding,
    required this.restoreLocator,
    required this.restoreProgression,
    required this.restoreToken,
    required this.onPosition,
    required this.onTapCenter,
    required this.onChapterChanged,
    required this.onBoundary,
    required this.onFootnote,
    required this.onReady,
    this.controller,
  });

  final ReaderContentController? controller;

  final ReaderChapterContent chapter;

  /// 已预渲染的相邻章，为空表示未备好，跨章翻页退回加载流程。
  final ReaderChapterContent? previous;
  final ReaderChapterContent? next;

  final bool paged;

  /// 正文四周留白，翻页模式下上下留白作用在每一页上。
  final EdgeInsets padding;

  final String? restoreLocator;
  final double restoreProgression;

  /// 上层要求重新定位（目录跳转、章节按钮）时自增，视图据此丢掉当前位置，
  /// 改按 [restoreLocator]/[restoreProgression] 定位。翻页导致的切章不改动它。
  final int restoreToken;

  final ValueChanged<ReaderContentPosition> onPosition;
  final VoidCallback onTapCenter;

  /// 翻页条进入了相邻章，上层据此平移窗口，正文不重排。
  final ValueChanged<int> onChapterChanged;

  /// 相邻章未备好时的越界翻页，交给上层翻章。
  final ValueChanged<bool> onBoundary;

  /// 脚注锚点所在的章与脚注 id。
  final void Function(int sortNum, String id) onFootnote;

  /// 当前章首次测量并定位完成。
  final VoidCallback onReady;

  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

/// 一次分片测量：要测的槽位、起始块与块数。`patch` 表示这是图片回填后的单块重测。
class _MeasureWindow {
  const _MeasureWindow(this.slot, this.start, this.count, {this.patch = false});

  final _ChapterSlot slot;
  final int start;
  final int count;
  final bool patch;

  bool sameAs(_MeasureWindow? other) =>
      other != null &&
      identical(other.slot, slot) &&
      other.start == start &&
      other.count == count &&
      other.patch == patch;
}

/// 一章在视图里的槽位，含正文块、测量层入口与测量结果。
class _ChapterSlot {
  _ChapterSlot(this.content);

  ReaderChapterContent content;
  final GlobalKey measureKey = GlobalKey();

  /// 正在按分片补齐的测量用正文块，下标与 `content.blocks` 对齐，未构建处为 null。
  /// 整章一次建完要把全章 HTML 扫一遍并分配几百个 widget，那是打开章节那一帧的大头。
  List<Widget?> pendingMeasure = const <Widget?>[];

  /// 与 [pendingMeasure] 一一对应的渲染用正文块，区别只在图片：测量层摆空盒子。
  List<Widget?> pendingContent = const <Widget?>[];

  /// 渲染层用的正文块，与 [geometry] 同一批换上，两者下标始终对得上。
  /// 换排版时先留着上一批，正文按旧样式多显示几帧，也不至于空屏。
  List<Widget> rendered = const <Widget>[];

  /// 逐块产出 markup 的游标，脚注编号跨块连续，只能顺序取。
  ReaderBlockMarkupBuilder? markupBuilder;
  int filled = 0;

  ReaderGeometry? geometry;
  List<double> pageTops = const <double>[0];

  /// 分片测量的累积器。测完整章后留着，供图片回填时改写单块。null 表示要从头测。
  ReaderGeometryBuilder? builder;

  /// 下一片测量的首个块下标。
  int cursor = 0;

  /// 图片回填真实尺寸后待重测的块。
  final Set<int> dirtyBlocks = <int>{};

  int get sortNum => content.sortNum;
  int get pageCount => pageTops.length;
  int get blockCount => pendingMeasure.length;

  /// 排版参数或正文变化后测量结果整章作废。
  void invalidate() {
    builder = null;
    cursor = 0;
    dirtyBlocks.clear();
  }

  bool get needsMeasure =>
      blockCount > 0 &&
      (builder == null || cursor < blockCount || dirtyBlocks.isNotEmpty);

  /// 测完一整章才把补齐的块与新几何一起换上。
  void publish(ReaderGeometry value) {
    geometry = value;
    rendered = List<Widget>.unmodifiable(pendingContent.cast<Widget>());
  }

  /// 有没有一批对得上的正文块与几何可以摆。
  bool get renderable =>
      geometry != null && rendered.length == geometry!.blockTops.length;
}

class _ReaderContentViewState extends State<ReaderContentView> {
  final List<_ChapterSlot> _slots = <_ChapterSlot>[];
  _ChapterSlot? _active;

  /// 翻页条：当前章与两侧已测量的章接成的全局页序。拖动期间冻结，
  /// 否则前一章中途接入会整体挪动当前页的全局下标。
  ReaderPageStrip<_ChapterSlot> _strip =
      const ReaderPageStrip<_ChapterSlot>.empty();
  bool _stripDirty = false;
  bool _scrolling = false;

  /// 已通知上层、窗口尚未平移的那一章。`jumpTo` 与惯性收尾会多次上报落定，用于去重。
  int? _notifiedChapter;

  Size _viewport = Size.zero;

  ScrollController? _scrollController;
  PageController? _pageController;

  /// 最近一次重排定下的滚动偏移，控制器未挂载时的上报用它。
  double _installedOffset = 0;

  bool _measureScheduled = false;
  int _measureAttempts = 0;
  bool _ready = false;

  /// 这一帧实际挂在测量层里的那一片。收集几何时照它读，不重新推算，
  /// 免得中途的 setState 让读取范围与挂载范围错位。
  _MeasureWindow? _mounted;

  String _locator = '';
  double _progression = 0;
  int _pageIndex = 0;

  int _reportedAt = 0;
  Timer? _trailingReport;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _resetSlots();
  }

  @override
  void didUpdateWidget(ReaderContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (widget.chapter.sortNum != oldWidget.chapter.sortNum) {
      _notifiedChapter = null;
    }
    final known = _slotFor(widget.chapter.sortNum);
    if (known == null ||
        !identical(known.content.blocks, widget.chapter.blocks)) {
      // 跳到窗口外的章节，正文全换，测量结果与位置作废。
      _resetSlots();
      return;
    }
    _syncSlots();
    if (oldWidget.paged != widget.paged ||
        oldWidget.padding != widget.padding) {
      for (final slot in _slots) {
        slot.invalidate();
      }
      _measureAttempts = 0;
    }
    if (widget.restoreToken != oldWidget.restoreToken) _restore();
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _trailingReport?.cancel();
    _scrollController?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  _ChapterSlot? _slotFor(int sortNum) {
    for (final slot in _slots) {
      if (slot.sortNum == sortNum) return slot;
    }
    return null;
  }

  void _resetSlots() {
    _slots.clear();
    _strip = const ReaderPageStrip<_ChapterSlot>.empty();
    _stripDirty = false;
    _locator = '';
    _progression = 0;
    _pageIndex = 0;
    _measureAttempts = 0;
    _ready = false;
    _active = null;
    _notifiedChapter = null;
    _syncSlots();
  }

  /// 按上层给的窗口重建槽位，同一章且正文未换的槽位连同测量结果留用。
  void _syncSlots() {
    final incoming = <ReaderChapterContent>[
      if (widget.previous != null) widget.previous!,
      widget.chapter,
      if (widget.next != null) widget.next!,
    ];
    final slots = <_ChapterSlot>[];
    for (final content in incoming) {
      final slot = _slotFor(content.sortNum);
      if (slot == null) {
        final created = _ChapterSlot(content);
        _rebuildBlocks(created);
        slots.add(created);
        continue;
      }
      final changed =
          !identical(slot.content.blocks, content.blocks) ||
          slot.content.style != content.style;
      slot.content = content;
      if (changed) {
        _rebuildBlocks(slot);
        _measureAttempts = 0;
      }
      slots.add(slot);
    }
    // 优先保留正在看的那一章，跨章翻页落定前上层还没切章。
    final active = _active;
    _slots
      ..clear()
      ..addAll(slots);
    _active =
        (active == null ? null : _slotFor(active.sortNum)) ??
        _slotFor(widget.chapter.sortNum);
  }

  /// 丢掉当前 locator，按新的恢复点重新定位当前章。
  void _restore() {
    _locator = '';
    _progression = widget.restoreProgression;
    _pageIndex = 0;
    _active = _slotFor(widget.chapter.sortNum) ?? _active;
    final slot = _active;
    final geometry = slot?.geometry;
    if (geometry == null) return;
    _syncStrip();
    _installControllers(_anchorOffset(geometry, _viewport));
    // didUpdateWidget 处于上层的 build 中，上报要等这一帧画完。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(force: true);
    });
  }

  void _rebuildBlocks(_ChapterSlot slot) {
    final count = slot.content.blocks.length;
    slot.pendingMeasure = List<Widget?>.filled(count, null);
    slot.pendingContent = List<Widget?>.filled(count, null);
    slot.markupBuilder = ReaderBlockMarkupBuilder(slot.content.style);
    slot.filled = 0;
    slot.invalidate();
  }

  /// 补齐到 [upTo]（含）为止的正文块。脚注编号跨块连续，只能顺序补。
  void _fillBlocks(_ChapterSlot slot, int upTo) {
    final content = slot.content;
    final markupBuilder = slot.markupBuilder!;
    final last = math.min(upTo, slot.blockCount - 1);
    for (var index = slot.filled; index <= last; index++) {
      final markup = markupBuilder.next(content.blocks[index]);
      final spacing = index + 1 < slot.blockCount;
      slot.pendingMeasure[index] = ReaderBlockBox(
        index: index,
        child: ReaderHtmlBlock(
          markup: markup,
          style: content.style,
          applyParagraphSpacing: spacing,
          measureOnly: true,
          // 几何只由测量层决定，回填尺寸也只从这一层通知，正文层那份不必再报一次。
          onLayoutChanged: () => _onBlockLayoutChanged(slot, index),
        ),
      );
      slot.pendingContent[index] = ReaderBlockBox(
        index: index,
        child: ReaderHtmlBlock(
          markup: markup,
          style: content.style,
          applyParagraphSpacing: spacing,
          onFootnote: (id) => widget.onFootnote(content.sortNum, id),
        ),
      );
      slot.filled = index + 1;
    }
  }

  /// 图片回填真实尺寸只改这一块的高度，重测单块后按前缀和平移后面的块。
  /// 还没测到这一块时什么都不用做，测到时自然用上新尺寸。
  void _onBlockLayoutChanged(_ChapterSlot slot, int index) {
    if (!mounted) return;
    final builder = slot.builder;
    if (builder == null || index >= builder.measured) return;
    if (!slot.dirtyBlocks.add(index)) return;
    setState(() => _measureAttempts = 0);
  }

  /// 相邻章等当前章就绪后再测，避免首屏排三章。
  bool _measurable(_ChapterSlot slot) => identical(slot, _active) || _ready;

  /// 一帧只测一片：块高彼此独立（测量层按固定正文宽度纵向堆叠），分片测量与整章
  /// 一次测量结果相同，而整章一次排完会让打开章节那一帧的布局涨到几十毫秒。
  ///
  /// 每片的目标耗时，留出余量给同一帧里的正文层与光栅化。
  static const double _sliceBudgetMs = 6;
  static const int _minSlice = 4;
  static const int _maxSlice = 24;

  int _slice = 12;

  /// 挂上测量层的时刻，用来量这一片实际花了多久，据此调整下一片的大小。
  /// 正文块长短差得远（几十字的对白到整段旁白），固定片长在长块上会超预算。
  final Stopwatch _sliceClock = Stopwatch();

  void _tuneSlice(int count) {
    if (!_sliceClock.isRunning) return;
    final elapsed = _sliceClock.elapsedMicroseconds / 1000;
    _sliceClock.stop();
    if (count <= 0 || elapsed <= 0) return;
    final perBlock = elapsed / count;
    _slice = (_sliceBudgetMs / perBlock).round().clamp(_minSlice, _maxSlice);
  }

  _MeasureWindow? _pickMeasureWindow() {
    final active = _active;
    for (final slot in <_ChapterSlot?>[active, ..._slots]) {
      if (slot == null || !slot.needsMeasure || !_measurable(slot)) continue;
      final total = slot.blockCount;
      final _MeasureWindow window;
      if (slot.builder == null || slot.cursor < total) {
        final start = slot.builder == null ? 0 : slot.cursor;
        window = _MeasureWindow(slot, start, math.min(_slice, total - start));
      } else {
        window = _MeasureWindow(slot, slot.dirtyBlocks.first, 1, patch: true);
      }
      _fillBlocks(slot, window.start + window.count - 1);
      return window;
    }
    return null;
  }

  void _scheduleMeasure(Size viewport) {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) _measure(viewport);
    });
  }

  /// 布局未就绪时再试一帧。`addPostFrameCallback` 不会催帧，需要主动请求一帧。
  void _retryMeasure(Size viewport) {
    if (_measureAttempts++ >= 5) return;
    _scheduleMeasure(viewport);
    WidgetsBinding.instance.scheduleFrame();
  }

  void _measure(Size viewport) {
    final window = _mounted;
    if (window == null || !window.sameAs(_pickMeasureWindow())) return;
    final root = window.slot.measureKey.currentContext?.findRenderObject();
    final metrics = root is RenderBox && root.hasSize
        ? collectReaderBlockMetrics(root, window.start, window.count)
        : null;
    if (metrics == null) {
      // 布局未就绪，或仍有块没排完（正文异步 build），再等一帧。重试有上限，避免空转掉帧。
      _sliceClock.stop();
      _retryMeasure(viewport);
      return;
    }
    _tuneSlice(window.count);
    _measureAttempts = 0;
    if (!_applyMetrics(window, metrics, viewport)) {
      // 这一章还没测完，下一帧接着测下一片。
      setState(() {});
      return;
    }

    final active = _active;
    final activeMeasured = identical(window.slot, active);
    setState(() {
      if (activeMeasured && active != null && active.geometry != null) {
        _syncStrip();
        _installControllers(_anchorOffset(active.geometry!, viewport));
      } else {
        _refreshStrip();
      }
    });

    _report(force: true);
    if (_ready || active?.geometry == null) return;
    _ready = true;
    widget.onReady();
  }

  /// 收下一片度量，返回这一章的几何是否因此更新。
  bool _applyMetrics(
    _MeasureWindow window,
    List<ReaderBlockMetrics> metrics,
    Size viewport,
  ) {
    final slot = window.slot;
    if (window.patch) {
      final changed = slot.builder!.patch(window.start, metrics.first);
      slot.dirtyBlocks.remove(window.start);
      if (!changed) return false;
    } else {
      final builder = slot.builder ??= ReaderGeometryBuilder();
      builder.add(metrics);
      slot.cursor = window.start + window.count;
      if (slot.cursor < slot.blockCount) return false;
    }
    slot.publish(slot.builder!.build());
    final geometry = slot.geometry!;
    slot.pageTops = widget.paged
        ? paginateReaderContent(
            contentHeight: geometry.height,
            pageHeight: viewport.height,
            breaks: geometry.breaks,
          )
        : const <double>[0];
    return true;
  }

  /// 重排后定位回当前 locator，首次进入才用上层给的进度。
  double _anchorOffset(ReaderGeometry geometry, Size viewport) {
    final slot = _active;
    if (slot == null) return 0;
    final locator = _locator.isNotEmpty
        ? _locator
        : (widget.restoreLocator ?? '');
    if (locator.isNotEmpty && geometry.blockTops.isNotEmpty) {
      final index = findReaderBlockIndex(slot.content.blocks, locator);
      if (index >= 0 && index < geometry.blockTops.length) {
        return geometry.blockTops[index];
      }
    }
    final progression =
        (_locator.isNotEmpty ? _progression : widget.restoreProgression).clamp(
          0.0,
          1.0,
        );
    return progression * math.max(0, geometry.height - viewport.height);
  }

  /// 当前章与两侧已测量的章接成翻页条。
  void _syncStrip() {
    final active = _active;
    if (active == null || active.geometry == null) {
      _strip = const ReaderPageStrip<_ChapterSlot>.empty();
      return;
    }
    final index = _slots.indexOf(active);
    var first = index;
    var last = index;
    while (first > 0 && _slots[first - 1].geometry != null) {
      first--;
    }
    while (last + 1 < _slots.length && _slots[last + 1].geometry != null) {
      last++;
    }
    _strip = ReaderPageStrip<_ChapterSlot>.of(
      _slots.sublist(first, last + 1),
      (slot) => slot.pageCount,
    );
  }

  /// 翻页条变化（相邻章测好、或窗口平移）后重排页序，并把控制器移到同一页上。
  /// 拖动期间只记脏，落定后再改，避免手指下的页码原地平移。
  void _refreshStrip() {
    if (_scrolling) {
      _stripDirty = true;
      return;
    }
    _stripDirty = false;
    _syncStrip();
    if (widget.paged) _installPageController();
  }

  int _globalPage() {
    final slot = _active;
    return slot == null ? 0 : _strip.globalPageOf(slot, _pageIndex);
  }

  void _installControllers(double offset) {
    _installedOffset = math.max(0, offset);
    _scrollController?.dispose();
    _scrollController = null;
    if (widget.paged) {
      final slot = _active;
      _pageIndex = slot == null
          ? 0
          : readerPageIndexForOffset(slot.pageTops, _installedOffset);
      _installPageController();
      return;
    }
    _pageController?.dispose();
    _pageController = null;
    // 控制器带初始偏移新建，避免先挂载再 jumpTo 造成一帧跳动。
    _scrollController = ScrollController(initialScrollOffset: _installedOffset)
      ..addListener(_onScroll);
  }

  /// 页序没挪动时留用同一个 `PageController`，换控制器会连 `PageView` 一起重建
  /// （见 [_pagedContent] 的 key）：`Scrollable` 认领新控制器时会沿用旧 position 的像素，
  /// `initialPage` 不生效，前一章接入翻页条后画面会停在错位的那一页上。
  void _installPageController() {
    final target = _globalPage();
    final controller = _pageController;
    if (controller != null &&
        controller.hasClients &&
        controller.page?.round() == target) {
      return;
    }
    controller?.dispose();
    _pageController = PageController(initialPage: target);
  }

  void _onScroll() => _report(force: false);

  bool _onPageScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _settle();
    }
    return false;
  }

  /// 翻页落定，补上挂起的翻页条改动，进入相邻章时通知上层平移窗口。
  void _settle() {
    if (_stripDirty) setState(_refreshStrip);
    final slot = _active;
    if (slot == null || slot.sortNum == widget.chapter.sortNum) return;
    if (_notifiedChapter == slot.sortNum) return;
    _notifiedChapter = slot.sortNum;
    widget.onChapterChanged(slot.sortNum);
  }

  void _applyPage(int page) {
    final located = _strip.locate(page);
    if (located == null) return;
    final (slot, local) = located;
    if (identical(slot, _active) && local == _pageIndex) return;
    _active = slot;
    _pageIndex = local;
    _report(force: true);
  }

  /// 250ms 节流上报，末尾补一次，避免漏报停下来的位置。
  void _report({required bool force}) {
    final slot = _active;
    final geometry = slot?.geometry;
    if (slot == null || geometry == null || !mounted) return;

    // 先算准 locator 与进度，跨章翻页后紧跟的重排要用它把位置定在新章上，
    // 节流只挡上报，不挡计算。
    final offset = _contentOffset(slot);
    final index = readerLocatorBlockIndex(
      blockTops: geometry.blockTops,
      blockBottoms: geometry.blockBottoms,
      offset: offset,
      paged: widget.paged,
      pageHeight: _viewport.height,
    );
    if (index < slot.content.blocks.length) {
      _locator = slot.content.blocks[index].locator;
    }
    if (widget.paged) {
      _progression = slot.pageCount <= 1
          ? 0
          : _pageIndex / (slot.pageCount - 1);
    } else {
      final maxOffset = math.max(0, geometry.height - _viewport.height);
      _progression = maxOffset <= 0 ? 0 : (offset / maxOffset).clamp(0.0, 1.0);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _reportedAt < 250) {
      _trailingReport ??= Timer(const Duration(milliseconds: 250), () {
        _trailingReport = null;
        _report(force: true);
      });
      return;
    }
    _trailingReport?.cancel();
    _trailingReport = null;
    _reportedAt = now;

    widget.onPosition(
      ReaderContentPosition(
        sortNum: slot.sortNum,
        locator: _locator,
        progression: _progression,
        page: widget.paged ? _pageIndex + 1 : 0,
        pages: widget.paged ? slot.pageCount : 0,
      ),
    );
  }

  double _contentOffset(_ChapterSlot slot) {
    if (widget.paged) {
      return _pageIndex < slot.pageCount ? slot.pageTops[_pageIndex] : 0;
    }
    final controller = _scrollController;
    // 控制器挂载前（重排后紧跟的那次上报）只有刚定下的偏移可用，读 0 会把定位打回章首。
    if (controller == null || !controller.hasClients) return _installedOffset;
    return math.max(0, controller.offset);
  }

  void _turn(bool next) {
    if (!widget.paged) {
      final controller = _scrollController;
      if (controller == null || !controller.hasClients) return;
      final position = controller.position;
      final boundary = next
          ? position.maxScrollExtent
          : position.minScrollExtent;
      if ((controller.offset - boundary).abs() < 0.5) {
        widget.onBoundary(next);
        return;
      }
      // 一步移动 95% 视口，再退到最近的行距处落定：当前屏最后一两行会留在下一屏顶上，
      // 接着读不会从半行开始。
      final step = position.viewportDimension * 0.95;
      // padding 在 ListView 内侧，换到几何坐标要减掉，落定时再加回来。
      final top = widget.padding.top;
      final raw = controller.offset - top + (next ? step : -step);
      final breaks = _active?.geometry?.breaks;
      final aligned = breaks == null
          ? raw
          : readerBreakAtMost(breaks, raw) ?? raw;
      controller.jumpTo(
        (aligned + top).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      return;
    }
    final controller = _pageController;
    final target = _globalPage() + (next ? 1 : -1);
    if (controller == null || target < 0 || target >= _strip.pages) {
      // 相邻章未接入翻页条，交给上层走加载流程。
      widget.onBoundary(next);
      return;
    }
    // 直接跳页而非动画。动画期间 PageView 的拖拽识别器会抢走下一次点按（该点按用于停住
    // 惯性滚动），连点翻页会丢一次。滑动翻页仍走 PageView 自己的动画。
    _applyPage(target);
    if (controller.hasClients) {
      // jumpTo 自带 start/end 通知，落定处理走 _onPageScroll。
      controller.jumpToPage(target);
      return;
    }
    // 重排刚换过控制器、PageView 还没挂载时调 `jumpToPage` 会触发 assert，
    // 改为换一个带新初始页的控制器，由下一帧的 PageView 认领。
    setState(_installPageController);
    _settle();
  }

  void _turnFromController(bool next) {
    if (_ready) _turn(next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(
        math.max(1, constraints.maxWidth - widget.padding.horizontal),
        math.max(1, constraints.maxHeight - widget.padding.vertical),
      );
      if (_viewport != viewport) {
        _viewport = viewport;
        for (final slot in _slots) {
          slot.invalidate();
        }
      }
      final window = _pickMeasureWindow();
      _mounted = window;
      if (window != null) {
        _sliceClock
          ..reset()
          ..start();
        _scheduleMeasure(viewport);
      }
      final active = _active;
      return Stack(
        children: <Widget>[
          // 测量层：只挂正在测的那一片，尺寸恒为 0，不绘制、不参与命中测试。
          //
          // 要带 key。测量层会随分片增删，Stack 的孩子没有 key 时按下标配对，正文层会
          // 被拿去复用测量层的 element，`PageView` 连同滚动位置一起重建，画面回到
          // `initialPage` 那一页。
          if (window != null)
            Positioned(
              key: const ValueKey<String>('reader-measure'),
              width: 0,
              height: 0,
              child: ExcludeSemantics(
                // 测量层只要尺寸，图片淡入之类的隐式动画不必在这里跑。
                child: TickerMode(
                  enabled: false,
                  child: ReaderMeasureBox(
                    width: viewport.width,
                    child: _measureColumn(window),
                  ),
                ),
              ),
            ),
          if (active != null && active.renderable)
            Positioned.fill(
              key: const ValueKey<String>('reader-content'),
              child: ReaderTapZoneLayer(
                onPrevious: () => _turn(false),
                onNext: () => _turn(true),
                onToggleChrome: widget.onTapCenter,
                // 滚动模式按上下分区：上一屏在上、下一屏在下，跟内容移动方向一致。
                axis: widget.paged ? Axis.horizontal : Axis.vertical,
                child: widget.paged
                    ? _pagedContent(viewport)
                    : _scrollingContent(active),
              ),
            ),
        ],
      );
    },
  );

  Widget _measureColumn(_MeasureWindow window) => Column(
    key: window.slot.measureKey,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (
        var index = window.start;
        index < window.start + window.count;
        index++
      )
        window.slot.pendingMeasure[index]!,
    ],
  );

  /// 滚动模式按测好的块高逐块建，整章一次性排完会让每次重绘都录一遍全章段落。
  Widget _scrollingContent(_ChapterSlot slot) {
    final geometry = slot.geometry!;
    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      itemCount: slot.rendered.length,
      itemExtentBuilder: (index, _) =>
          geometry.blockBottoms[index] - geometry.blockTops[index],
      itemBuilder: (context, index) => slot.rendered[index],
    );
  }

  Widget _pagedContent(Size viewport) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onPageScroll,
        child: PageView.builder(
          key: ObjectKey(_pageController),
          controller: _pageController,
          itemCount: _strip.pages,
          onPageChanged: _applyPage,
          itemBuilder: (context, index) {
            final located = _strip.locate(index);
            if (located == null) return const SizedBox.shrink();
            final slot = located.$1;
            return ReaderPageBody(
              sortNum: slot.sortNum,
              geometry: slot.geometry,
              pageTops: slot.pageTops,
              blocks: slot.rendered,
              renderable: slot.renderable,
              index: located.$2,
              viewport: viewport,
              padding: widget.padding,
            );
          },
        ),
      );
}
