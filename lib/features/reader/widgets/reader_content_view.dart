import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/settings/app_settings.dart';
import '../../../shared/widgets/html/reader_content_style.dart';
import '../../../shared/widgets/html/html_source.dart';
import '../../../shared/widgets/reader_html_block.dart';
import '../reader_block_markup.dart';
import '../reader_pagination.dart';
import '../reader_page_turn.dart';
import '../reader_position.dart';
import 'reader_measure_box.dart';
import 'reader_page_body.dart';
import 'reader_tap_zone.dart';

final RegExp _spacedReaderTextBlock = RegExp(
  r'^\s*<(?:p|h[1-6])\b',
  caseSensitive: false,
);

double _readerBlockSpacing(
  ReaderBlock block,
  ReaderBlock? next,
  double lineSpace,
) {
  if (next == null || lineSpace <= 0) return 0;
  if (block is ReaderImageBlock) return 0;
  return _spacedReaderTextBlock.hasMatch(block.html) ? lineSpace : 0;
}

/// 一章正文及其排版参数。正文字形逐章混淆，字体各章不同，所以样式随章走。
class ReaderChapterContent {
  const ReaderChapterContent({
    required this.sortNum,
    required this.blocks,
    required this.style,
  });

  final int sortNum;
  final List<ReaderBlock> blocks;
  final ReaderContentStyle style;
}

/// 正文位置上报。`page`/`pages` 从 1 开始，滚动模式恒为 0。
/// 位置一律记在屏首那一栏上，所以自带该栏所属的 [sortNum]。
class ReaderContentPosition {
  const ReaderContentPosition({
    required this.sortNum,
    required this.tailSortNum,
    required this.locator,
    required this.progression,
    required this.page,
    required this.pages,
  });

  /// 屏首那一栏所属的章。
  final int sortNum;

  /// 屏尾那一栏所属的章；一屏只有一栏或没跨章时与 [sortNum] 相同。
  final int tailSortNum;

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
/// [chapters] 里的每一章各有自己的测量层，测完后首尾相接组成翻页条，跨章翻页即走到条上的
/// 下一栏，落定后由 [onChapterChanged] 通知上层挪动当前章。
///
/// 翻页条两端之外若还有章，各补一段加载栏：栏上转圈，并通过 [onNeedChapter] 请求上层把
/// 那一章接进来。请求只在加载栏真的露在当前屏上时发出，所以关掉预加载时，单页要翻到章尾
/// 之后才请求，双页则在右栏空出来的那一刻就请求。
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.chapters,
    required this.sortNum,
    required this.paged,
    required this.dualPage,
    required this.padding,
    required this.restoreLocator,
    required this.restoreProgression,
    required this.restoreToken,
    required this.onPosition,
    required this.onTapCenter,
    required this.onChapterChanged,
    required this.onBoundary,
    required this.onNeedChapter,
    required this.onFootnote,
    required this.onReady,
    this.totalChapters = 0,
    this.failedChapters = const <int>{},
    this.controller,
    this.pageTurnAnimation = ReaderPageTurnAnimation.none,
  });

  final ReaderContentController? controller;

  /// 已备好的连续章节，按章号升序，必须含 [sortNum] 那一章。
  final List<ReaderChapterContent> chapters;

  /// 当前章章号。
  final int sortNum;

  ReaderChapterContent get chapter =>
      chapters.firstWhere((chapter) => chapter.sortNum == sortNum);

  /// 全书章数，0 表示未知。用来判断翻页条两端之外还有没有章可接。
  final int totalChapters;

  /// 取失败的章号，加载栏改摆重试块。
  final Set<int> failedChapters;

  final bool paged;

  /// 点击或外部控制器触发翻页时使用的动画；手势拖动仍由 [PageView] 处理。
  final ReaderPageTurnAnimation pageTurnAnimation;

  /// 翻页模式下是否把一屏拆成两栏，只在大屏横屏时真的分栏。
  final bool dualPage;

  /// 正文四周留白，翻页模式下上下留白作用在每一页上。
  final EdgeInsets padding;

  final String? restoreLocator;
  final double restoreProgression;

  /// 上层要求重新定位（目录跳转、章节按钮）时自增，视图据此丢掉当前位置，
  /// 改按 [restoreLocator]/[restoreProgression] 定位。翻页导致的切章不改动它。
  final int restoreToken;

  final ValueChanged<ReaderContentPosition> onPosition;
  final VoidCallback onTapCenter;

  /// 翻页条进入了另一章，上层据此挪动当前章，正文不重排。
  final ValueChanged<int> onChapterChanged;

  /// 滚动模式读到头还要继续翻，交给上层换章。
  final ValueChanged<bool> onBoundary;

  /// 当前屏上露出了加载栏：请求 [fromSortNum] 往 [next] 方向的下一章。
  /// 同一章只请求一次，除非它进了 [failedChapters] 且用户点了重试。
  final void Function(bool next, int fromSortNum) onNeedChapter;

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

  /// 每一栏的页顶。翻页条按栏走，一屏摆几栏由视口决定，与章节无关。
  List<double> pageTops = const <double>[0];

  /// 分片测量的累积器。测完整章后留着，供图片回填时改写单块。null 表示要从头测。
  ReaderGeometryBuilder? builder;

  /// 下一片测量的首个块下标。
  int cursor = 0;

  /// 图片回填真实尺寸后待重测的块。
  final Set<int> dirtyBlocks = <int>{};

  int get sortNum => content.sortNum;

  /// 这一章占翻页条上的栏数。
  int get columnCount => pageTops.length;

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

  /// 当前视口下的分栏数，测量层照它取正文宽度。
  int _columns = 1;

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

  /// 停在翻页条之外的加载栏上：-1 在条前，1 在条后，0 表示位置落在真正的栏上。
  int _pendingSide = 0;

  /// 进加载栏时条端上的那一章，等它的邻章接进条里就落到那一章上。
  _ChapterSlot? _pendingEdge;

  /// 已经请求过的相邻章，同一章不重复通知上层。
  final Set<int> _requested = <int>{};
  bool _requestScheduled = false;

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
    if (widget.sortNum != oldWidget.sortNum) {
      _notifiedChapter = null;
    }
    final known = _slotFor(widget.sortNum);
    if (known == null ||
        !identical(known.content.blocks, widget.chapter.blocks)) {
      // 跳到窗口外的章节，正文全换，测量结果与位置作废。
      _resetSlots();
      return;
    }
    // 接进来的章不必再请求；被丢出窗口的章回头还能再请求一次。
    _requested.removeWhere(
      (sortNum) => widget.chapters.any((chapter) => chapter.sortNum == sortNum),
    );
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
    _pendingSide = 0;
    _pendingEdge = null;
    _requested.clear();
    _syncSlots();
  }

  /// 按上层给的窗口重建槽位，同一章且正文未换的槽位连同测量结果留用。
  void _syncSlots() {
    final slots = <_ChapterSlot>[];
    for (final content in widget.chapters) {
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
    // 优先保留正在看的那一章，跨章翻页落定前上层还没挪当前章。
    final active = _active;
    _slots
      ..clear()
      ..addAll(slots);
    _active =
        (active == null ? null : _slotFor(active.sortNum)) ??
        _slotFor(widget.sortNum);
    final edge = _pendingEdge;
    if (edge != null && !_slots.contains(edge)) {
      _pendingSide = 0;
      _pendingEdge = null;
    }
  }

  /// 丢掉当前 locator，按新的恢复点重新定位当前章。
  void _restore() {
    _locator = '';
    _progression = widget.restoreProgression;
    _pageIndex = 0;
    _pendingSide = 0;
    _pendingEdge = null;
    _active = _slotFor(widget.sortNum) ?? _active;
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
      final block = content.blocks[index];
      final next = index + 1 < slot.blockCount
          ? content.blocks[index + 1]
          : null;
      final markup = markupBuilder.next(block);
      final spacing = _readerBlockSpacing(block, next, content.style.lineSpace);
      slot.pendingMeasure[index] = ReaderBlockBox(
        index: index,
        child: ReaderHtmlBlock(
          markup: markup,
          style: content.style,
          bottomSpacing: spacing,
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
          bottomSpacing: spacing,
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

  /// 用户正在加载栏上等的那一章：条端那一章的邻章。测量先排它，
  /// 免得先去排另一侧的章，让加载栏多转一会儿。
  _ChapterSlot? get _awaited {
    final edge = _pendingEdge;
    if (edge == null) return null;
    final index = _slots.indexOf(edge) + _pendingSide;
    return index < 0 || index >= _slots.length ? null : _slots[index];
  }

  _MeasureWindow? _pickMeasureWindow() {
    final active = _active;
    for (final slot in <_ChapterSlot?>[active, _awaited, ..._slots]) {
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

    _syncPosition();
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
      (slot) => slot.columnCount,
    );
  }

  /// 锚点栏在翻页条上的下标。
  int _anchorColumn() {
    final slot = _active;
    return slot == null ? 0 : _strip.globalPageOf(slot, _pageIndex);
  }

  /// 锚点栏在整条（含条前的加载栏）上的下标。
  int _globalColumn() => _leadingPending + _anchorColumn();

  /// 翻页条最前面那一章之前还有没有章。
  bool get _hasChapterBefore =>
      !_strip.isEmpty && _strip.chapters.first.sortNum > 1;

  /// 翻页条最后那一章之后还有没有章；[ReaderContentView.totalChapters] 为 0 表示总数未知。
  bool get _hasChapterAfter =>
      !_strip.isEmpty &&
      (widget.totalChapters == 0 ||
          _strip.chapters.last.sortNum < widget.totalChapters);

  /// 条前补几栏加载栏：补到让锚点栏正好落在屏首。
  ///
  /// 章节进出窗口会让翻页条整体前后挪，补齐这几栏，屏上那两栏才不会跟着重新配对、
  /// 画面跳一下。书首之前没有章可等，也就不补。
  int get _leadingPending =>
      _hasChapterBefore ? (-_anchorColumn() - 1) % _columns + 1 : 0;

  /// 条后只补一栏：接进来的章从这一栏起摆，接不满的那半屏留白。
  int get _trailingPending => _hasChapterAfter ? 1 : 0;

  /// 一屏摆 [_columns] 栏，栏在条上首尾相接，所以屏的划分与章节边界无关：
  /// 只剩一栏的章节（整页插图）右边不再空着，接的是下一章的第一栏。
  int get _screenCount =>
      (_leadingPending + _strip.pages + _trailingPending + _columns - 1) ~/
      _columns;

  int _screenIndex() {
    if (_pendingSide < 0) return 0;
    if (_pendingSide > 0) {
      return (_leadingPending + _strip.pages) ~/ _columns;
    }
    return _globalColumn() ~/ _columns;
  }

  /// 翻页条变化（相邻章测好、或窗口挪动）后重排页序，并把控制器移到同一页上。
  /// 拖动期间只记脏，落定后再改，避免手指下的页码原地平移。
  void _refreshStrip() {
    if (_scrolling) {
      _stripDirty = true;
      return;
    }
    _stripDirty = false;
    _syncStrip();
    _resolvePending();
    if (widget.paged) {
      _installPageController();
      _anchorToScreenHead();
    }
  }

  /// 等的那一章接进翻页条后，把位置从加载栏落到它上面：往后落在章首，往前落在章末。
  void _resolvePending() {
    final side = _pendingSide;
    final target = _awaited;
    if (side == 0 || target == null || target.geometry == null) return;
    if (!_strip.chapters.contains(target)) return;
    _pendingSide = 0;
    _pendingEdge = null;
    _active = target;
    _pageIndex = side < 0 ? target.columnCount - 1 : 0;
  }

  /// 把位置钉到当前屏最左那一栏：页码与进度一律按屏首那一章算，
  /// 所以双页时最后一屏的进度到不了 100%。
  void _anchorToScreenHead() {
    if (_pendingSide != 0) return;
    final column = _screenIndex() * _columns - _leadingPending;
    final located = column < 0 ? null : _strip.locate(column);
    if (located == null) return;
    final (slot, page) = located;
    _active = slot;
    _pageIndex = page;
  }

  /// 上报当前位置；屏首换了一章就先通知上层挪当前章，否则上层会把这次上报当成
  /// 别的章的丢掉，页码胶囊停在旧章上。调用点都在 setState 之外。
  void _syncPosition() {
    _notifyChapter();
    _report(force: true);
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
      _anchorToScreenHead();
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
    final target = _screenIndex();
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

  /// 翻页落定，补上挂起的翻页条改动，并把位置同步给上层。
  void _settle() {
    if (_stripDirty) setState(_refreshStrip);
    _syncPosition();
  }

  void _notifyChapter() {
    final slot = _active;
    if (slot == null || slot.sortNum == widget.sortNum) return;
    if (_notifiedChapter == slot.sortNum) return;
    _notifiedChapter = slot.sortNum;
    widget.onChapterChanged(slot.sortNum);
  }

  /// 落定到第 [screen] 屏：位置记在这一屏最左那一栏上，落在加载栏上时仍记在条端那一章。
  void _applyPage(int screen) {
    final column = screen * _columns - _leadingPending;
    final located = column < 0 ? null : _strip.locate(column);
    if (located == null) {
      final side = column < 0 ? -1 : 1;
      if (_pendingSide != side && !_strip.isEmpty) {
        setState(() {
          _pendingSide = side;
          _pendingEdge = side < 0
              ? _strip.chapters.first
              : _strip.chapters.last;
        });
      }
      _scheduleRequest();
      return;
    }
    if (_pendingSide != 0) {
      setState(() {
        _pendingSide = 0;
        _pendingEdge = null;
      });
    }
    _scheduleRequest();
    final (slot, local) = located;
    if (identical(slot, _active) && local == _pageIndex) return;
    _active = slot;
    _pageIndex = local;
    _syncPosition();
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
      _progression = slot.columnCount <= 1
          ? 0
          : _pageIndex / (slot.columnCount - 1);
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
        tailSortNum: _tailSlot()?.sortNum ?? slot.sortNum,
        locator: _locator,
        progression: _progression,
        page: widget.paged ? _pageIndex + 1 : 0,
        pages: widget.paged ? slot.columnCount : 0,
      ),
    );
  }

  /// 当前屏最后一栏落在的那一章。屏尾是加载栏或留白时取翻页条上最后那一章，
  /// 上层照它决定往后再备哪一章。
  _ChapterSlot? _tailSlot() {
    if (!widget.paged || _strip.isEmpty) return null;
    final first = _screenIndex() * _columns - _leadingPending;
    final column = math.min(first + _columns - 1, _strip.pages - 1);
    return column < 0 ? null : _strip.locate(column)?.$1;
  }

  double _contentOffset(_ChapterSlot slot) {
    if (widget.paged) {
      return _pageIndex < slot.pageTops.length ? slot.pageTops[_pageIndex] : 0;
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
    final target = _screenIndex() + (next ? 1 : -1);
    if (controller == null || target < 0 || target >= _screenCount) {
      // 条外没有栏可翻了：滚动模式交给上层换章，翻页模式此处已是全书两端。
      widget.onBoundary(next);
      return;
    }
    _applyPage(target);
    if (controller.hasClients) {
      turnReaderPage(controller, target, widget.pageTurnAnimation);
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

  /// 当前屏上露出加载栏时请求那一章。相邻章的按需请求只有这一个入口：
  /// 翻到加载栏、以及双页时右栏空出来，都走它。
  void _scheduleRequest() {
    if (_requestScheduled) return;
    _requestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScheduled = false;
      if (mounted) _requestVisiblePending();
    });
  }

  void _requestVisiblePending() {
    if (!widget.paged || _strip.isEmpty || !_ready) return;
    final first = _screenIndex() * _columns - _leadingPending;
    final next = first + _columns - 1 >= _strip.pages && _hasChapterAfter;
    final previous = first < 0 && _hasChapterBefore;
    if (!next && !previous) return;
    final edge = next ? _strip.chapters.last : _strip.chapters.first;
    if (!_requested.add(edge.sortNum + (next ? 1 : -1))) return;
    widget.onNeedChapter(next, edge.sortNum);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(
        math.max(1, constraints.maxWidth - widget.padding.horizontal),
        math.max(1, constraints.maxHeight - widget.padding.vertical),
      );
      final columns = widget.paged
          ? readerColumnCount(
              dualPage: widget.dualPage,
              width: viewport.width,
              height: viewport.height,
              fontSize: widget.chapter.style.fontSize,
            )
          : 1;
      if (_viewport != viewport || _columns != columns) {
        _viewport = viewport;
        _columns = columns;
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
      _scheduleRequest();
      final active = _active;
      final content = Stack(
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
                    width: _columnWidth(viewport),
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
      // 翻页模式下正文层与测量层共用同一个图片高度上限，几何才对得上。
      return widget.paged
          ? ReaderImageBounds(maxHeight: viewport.height, child: content)
          : content;
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
      key: ObjectKey(_scrollController),
      controller: _scrollController,
      padding: widget.padding,
      itemCount: slot.rendered.length,
      itemExtentBuilder: (index, _) =>
          geometry.blockBottoms[index] - geometry.blockTops[index],
      itemBuilder: (context, index) => slot.rendered[index],
    );
  }

  /// 一栏的正文宽度：栏间距摊在栏与栏之间，两侧留白仍归 [ReaderContentView.padding]。
  double _columnWidth(Size viewport) =>
      (viewport.width - readerColumnGutter * (_columns - 1)) / _columns;

  /// 双页模式下每一栏的留白：外侧照旧，内侧各占一半栏间距。
  EdgeInsets _columnPadding(int column, int columns) {
    if (columns <= 1) return widget.padding;
    final inner = readerColumnGutter / 2;
    return EdgeInsets.only(
      left: column == 0 ? widget.padding.left : inner,
      top: widget.padding.top,
      right: column == columns - 1 ? widget.padding.right : inner,
      bottom: widget.padding.bottom,
    );
  }

  Widget _pagedContent(Size viewport) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onPageScroll,
        child: PageView.builder(
          key: ObjectKey(_pageController),
          controller: _pageController,
          itemCount: _screenCount,
          onPageChanged: _applyPage,
          itemBuilder: (context, screen) {
            if (_columns <= 1) return _pageColumn(screen, viewport, 0, 1);
            return Row(
              children: <Widget>[
                for (var column = 0; column < _columns; column++)
                  Expanded(
                    child: _pageColumn(
                      screen * _columns + column,
                      viewport,
                      column,
                      _columns,
                    ),
                  ),
              ],
            );
          },
        ),
      );

  /// 整条上第 [globalColumn] 栏：落在翻页条上的摆正文，落在条外的摆加载栏。
  Widget _pageColumn(int globalColumn, Size viewport, int column, int columns) {
    final padding = _columnPadding(column, columns);
    final index = globalColumn - _leadingPending;
    final located = index < 0 ? null : _strip.locate(index);
    if (located == null) {
      // 加载栏只在紧挨着翻页条、且那个方向确实还有章时才转圈：同一屏里更远的那些留白，
      // 全书末章后面半屏空着也留白，没有下一章可等。
      final before = index < 0;
      final spinner = before
          ? index == -1 && _hasChapterBefore
          : index == _strip.pages && _hasChapterAfter;
      if (!spinner) return const SizedBox.shrink();
      final edge = before ? _strip.chapters.first : _strip.chapters.last;
      return _pendingColumn(edge.sortNum + (before ? -1 : 1), padding);
    }
    final (slot, page) = located;
    return ReaderPageBody(
      sortNum: slot.sortNum,
      geometry: slot.geometry,
      pageTops: slot.pageTops,
      blocks: slot.rendered,
      renderable: slot.renderable,
      index: page,
      viewport: viewport,
      padding: padding,
    );
  }

  /// 还没备好的那一章占的栏：转圈等着，取失败了改成点一下重试。
  Widget _pendingColumn(int sortNum, EdgeInsets padding) => Padding(
    padding: padding,
    child: Center(
      child: widget.failedChapters.contains(sortNum)
          ? TextButton(
              onPressed: () {
                setState(() => _requested.remove(sortNum));
                _scheduleRequest();
              },
              child: const Text('加载失败，点击重试'),
            )
          : const CircularProgressIndicator(),
    ),
  );
}
