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
import 'reader_tap_zone.dart';

/// 一章正文及其排版参数。章节字体各章不同（正文字形是逐章混淆的），
/// 所以样式随章走，而不是整个阅读器共用一份。
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
/// 跨章翻页时先于上层切章，因此必须自带 [sortNum]。
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

/// 某一页的绘制区域；高度就是该页实际占用的正文高度，末尾空白不在其内。
Key readerPageBodyKey(int sortNum, int index) =>
    ValueKey<String>('reader-page-$sortNum-$index');

/// 原生正文视图。
///
/// 正文用 `HtmlWidget` 渲染，翻页与定位由 Flutter 侧完成：先把整章排在一个零尺寸的
/// 测量层里，读出每个块的纵向区间与每一行的行顶，再按视口高度切页；翻页模式的每一页
/// 只把落在该页区间的块按测量偏移摆进 `Stack` 并裁掉溢出，行的位置与测量层逐像素一致。
/// 排版/视口/图片尺寸变化都会重新测量，并把阅读位置钉回当前 locator。
///
/// 前后章一并预渲染：[previous]/[next] 各有自己的测量层，测完就把页接在当前章两端，
/// 拼成一条连续的翻页条。跨章翻页因此只是走到条上的下一页——不重排、不加载、不闪屏，
/// 落定后由 [onChapterChanged] 通知上层把窗口挪过去。相邻章还没备好时越界翻页仍走
/// [onBoundary] 的加载流程。
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
  });

  final ReaderChapterContent chapter;

  /// 已预渲染好的相邻章；为空表示还没备好，跨章翻页退回加载流程。
  final ReaderChapterContent? previous;
  final ReaderChapterContent? next;

  final bool paged;

  /// 正文四周留白：翻页模式下上下留白作用在每一页上。
  final EdgeInsets padding;

  final String? restoreLocator;
  final double restoreProgression;

  /// 上层要求重新定位（目录跳转、章节按钮）时自增：视图据此丢掉当前位置，
  /// 改按 [restoreLocator]/[restoreProgression] 重新钉。翻页翻出来的切章不动它。
  final int restoreToken;

  final ValueChanged<ReaderContentPosition> onPosition;
  final VoidCallback onTapCenter;

  /// 翻页条走进了相邻章：上层把窗口挪过去，正文不重排。
  final ValueChanged<int> onChapterChanged;

  /// 相邻章没备好时的越界翻页：交给上层翻章。
  final ValueChanged<bool> onBoundary;

  /// 脚注锚点所在的章与脚注 id。
  final void Function(int sortNum, String id) onFootnote;

  /// 当前章首次测量并定位完成。
  final VoidCallback onReady;

  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

/// 一章在视图里的槽位：正文块、自己的测量层入口与测量结果。
class _ChapterSlot {
  _ChapterSlot(this.content);

  ReaderChapterContent content;
  final GlobalKey measureKey = GlobalKey();

  List<Widget> blockWidgets = const <Widget>[];
  ReaderGeometry? geometry;
  List<double> pageTops = const <double>[0];

  /// 排版参数变了、测量结果已经不作数。
  bool stale = true;

  int get sortNum => content.sortNum;
  int get pageCount => pageTops.length;

  /// 换过样式的那一帧里正文块已重建、几何还是旧的，块数对不上就不能照它摆块。
  bool get renderable {
    final geometry = this.geometry;
    return geometry != null && geometry.blockTops.length == blockWidgets.length;
  }
}

class _ReaderContentViewState extends State<ReaderContentView> {
  final List<_ChapterSlot> _slots = <_ChapterSlot>[];
  _ChapterSlot? _active;

  /// 翻页条：当前章与两侧已测量好的章接成的全局页序。拖动期间冻结——
  /// 前一章半路接进来会把当前页的全局下标整体挪走，手指底下就跳了。
  ReaderPageStrip<_ChapterSlot> _strip =
      const ReaderPageStrip<_ChapterSlot>.empty();
  bool _stripDirty = false;
  bool _scrolling = false;

  /// 已经通知过上层、但窗口还没挪过来的那一章：`jumpTo` 与惯性收尾会连报几次
  /// 落定，重复通知没有意义。
  int? _notifiedChapter;

  Size _viewport = Size.zero;

  ScrollController? _scrollController;
  PageController? _pageController;

  /// 最近一次重排钉下的滚动偏移，控制器还没挂载时的上报靠它。
  double _installedOffset = 0;

  bool _measureScheduled = false;
  int _measureAttempts = 0;
  bool _ready = false;

  String _locator = '';
  double _progression = 0;
  int _pageIndex = 0;

  int _reportedAt = 0;
  Timer? _trailingReport;

  @override
  void initState() {
    super.initState();
    _resetSlots();
  }

  @override
  void didUpdateWidget(ReaderContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chapter.sortNum != oldWidget.chapter.sortNum) {
      _notifiedChapter = null;
    }
    final known = _slotFor(widget.chapter.sortNum);
    if (known == null ||
        !identical(known.content.blocks, widget.chapter.blocks)) {
      // 跳到窗口外的章节：正文全换，测量结果与位置一律作废。
      _resetSlots();
      return;
    }
    _syncSlots();
    if (oldWidget.paged != widget.paged ||
        oldWidget.padding != widget.padding) {
      for (final slot in _slots) {
        slot.stale = true;
      }
      _measureAttempts = 0;
    }
    if (widget.restoreToken != oldWidget.restoreToken) _restore();
  }

  @override
  void dispose() {
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

  /// 按上层给的窗口重建槽位：同一章且正文没换的槽位连同测量结果一起留用，
  /// 窗口平移（跨章翻页后）因此不会触发任何重排。
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
        slot.stale = true;
        _measureAttempts = 0;
      }
      slots.add(slot);
    }
    // 正在看的那一章优先：跨章翻页落定前上层还没切过来，别把位置拽回去。
    final active = _active;
    _slots
      ..clear()
      ..addAll(slots);
    _active =
        (active == null ? null : _slotFor(active.sortNum)) ??
        _slotFor(widget.chapter.sortNum);
  }

  /// 上层要求重新定位：丢掉当前 locator，按新的恢复点把当前章钉回去。
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
    // didUpdateWidget 还在上层的 build 里，上报必须等这一帧画完。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(force: true);
    });
  }

  void _rebuildBlocks(_ChapterSlot slot) {
    final content = slot.content;
    final markup = buildReaderBlockMarkup(content.blocks, content.style);
    slot.blockWidgets = <Widget>[
      for (var index = 0; index < markup.length; index++)
        ReaderBlockBox(
          index: index,
          child: ReaderHtmlBlock(
            markup: markup[index],
            style: content.style,
            applyParagraphSpacing: index + 1 < markup.length,
            onFootnote: (id) => widget.onFootnote(content.sortNum, id),
            onLayoutChanged: () => _onBlockLayoutChanged(slot),
          ),
        ),
    ];
  }

  void _onBlockLayoutChanged(_ChapterSlot slot) {
    if (!mounted) return;
    setState(() {
      slot.stale = true;
      _measureAttempts = 0;
    });
  }

  /// 相邻章的测量层要等当前章就绪后再挂：首屏只排一章，别被三章的排版拖慢。
  bool _measurable(_ChapterSlot slot) => identical(slot, _active) || _ready;

  void _scheduleMeasure(Size viewport) {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) _measure(viewport);
    });
  }

  /// 布局没就绪时再试一帧。`addPostFrameCallback` 自己不会催帧，得主动要一帧。
  void _retryMeasure(Size viewport) {
    if (_measureAttempts++ >= 5) return;
    _scheduleMeasure(viewport);
    WidgetsBinding.instance.scheduleFrame();
  }

  void _measure(Size viewport) {
    if (_viewport != viewport) {
      for (final slot in _slots) {
        slot.stale = true;
      }
    }
    final active = _active;
    var activeMeasured = false;
    var changed = false;
    var pending = false;
    for (final slot in _slots) {
      if (!slot.stale || !_measurable(slot)) continue;
      final root = slot.measureKey.currentContext?.findRenderObject();
      final geometry = root is RenderBox && root.hasSize
          ? collectReaderGeometry(root, slot.blockWidgets.length)
          : null;
      if (geometry == null) {
        // 布局没就绪，或还有块没排完（异步 build 的正文），再等一帧；
        // 重试有上限，免得空转掉帧。
        pending = true;
        continue;
      }
      slot.geometry = geometry;
      slot.pageTops = widget.paged
          ? paginateReaderContent(
              contentHeight: geometry.height,
              pageHeight: viewport.height,
              breaks: geometry.breaks,
            )
          : const <double>[0];
      slot.stale = false;
      changed = true;
      if (identical(slot, active)) activeMeasured = true;
    }
    if (!changed) {
      if (pending) _retryMeasure(viewport);
      return;
    }

    setState(() {
      _viewport = viewport;
      _measureAttempts = 0;
      if (activeMeasured && active != null) {
        _syncStrip();
        _installControllers(_anchorOffset(active.geometry!, viewport));
      } else {
        _refreshStrip();
      }
    });
    if (pending) _retryMeasure(viewport);

    _report(force: true);
    if (_ready || active?.geometry == null) return;
    _ready = true;
    widget.onReady();
  }

  /// 重排后钉回当前 locator；首次进入才用上层给的进度。
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

  /// 当前章与两侧已测量好的章接成翻页条。
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

  /// 翻页条变了（相邻章测好了、或窗口挪过）：重排页序并把控制器挪到同一页上。
  /// 拖动期间只记脏，落定后再改，免得手指底下的页码原地平移。
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
    // 控制器带着初始偏移新建，省掉「先挂载再 jumpTo」那一帧的跳动。
    _scrollController = ScrollController(initialScrollOffset: _installedOffset)
      ..addListener(_onScroll);
  }

  /// 换控制器必须连 `PageView` 一起换（见 [_pagedContent] 的 key）：`Scrollable`
  /// 认领新控制器时会把旧 position 的像素原样吸收过来，`initialPage` 形同虚设，
  /// 前一章接进翻页条后页序整体后移，画面就会停在错位的那一页上。
  void _installPageController() {
    _pageController?.dispose();
    _pageController = PageController(initialPage: _globalPage());
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

  /// 翻页落定：迟到的翻页条改动补上，走进相邻章就通知上层挪窗口。
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

  /// 与旧 WebView 版本一致的 250ms 节流，尾巴上补一次，停下来的位置不会漏报。
  void _report({required bool force}) {
    final slot = _active;
    final geometry = slot?.geometry;
    if (slot == null || geometry == null || !mounted) return;

    // locator 与进度先算准：跨章翻页后紧跟的重排要靠它把位置钉在新章上，
    // 节流只挡上报，不挡计算。
    final offset = _contentOffset(slot);
    final index = _locatorIndex(slot, geometry, offset);
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

  /// 进度落在哪个块上。
  ///
  /// 翻页模式下页顶那个块常常是从上一页跨过来的：进度要记在本页第一个整块上，
  /// 否则按 locator 重开会退回上一页，报出去的位置也不再幂等。
  int _locatorIndex(_ChapterSlot slot, ReaderGeometry geometry, double offset) {
    final index = readerBlockIndexAtOffset(
      blockTops: geometry.blockTops,
      blockBottoms: geometry.blockBottoms,
      offset: offset + 1,
    );
    if (!widget.paged) return index;
    var candidate = index;
    while (candidate < geometry.blockTops.length &&
        geometry.blockTops[candidate] < offset - 0.5) {
      candidate++;
    }
    // 整块都挤不进本页（跨多页的长段/整页插图）时，仍以跨页那个块为准。
    return candidate < geometry.blockTops.length &&
            geometry.blockTops[candidate] < offset + _viewport.height
        ? candidate
        : index;
  }

  double _contentOffset(_ChapterSlot slot) {
    if (widget.paged) {
      return _pageIndex < slot.pageCount ? slot.pageTops[_pageIndex] : 0;
    }
    final controller = _scrollController;
    // 控制器挂载前（重排后紧跟的那次上报）只有刚钉下的偏移可用，读 0 会把定位打回章首。
    if (controller == null || !controller.hasClients) return _installedOffset;
    return math.max(0, controller.offset);
  }

  void _turn(bool next) {
    final controller = _pageController;
    final target = _globalPage() + (next ? 1 : -1);
    if (controller == null || target < 0 || target >= _strip.pages) {
      // 相邻章还没接进翻页条：交给上层走加载流程。
      widget.onBoundary(next);
      return;
    }
    // 直接跳页而不是动画：动画期间 PageView 的拖拽识别器会抢下一次点按（原本用来
    // 停住惯性滚动），连点翻页就会丢一次。滑动翻页仍走 PageView 自己的动画。
    _applyPage(target);
    if (controller.hasClients) {
      // jumpTo 自带 start/end 通知，落定处理走 _onPageScroll。
      controller.jumpToPage(target);
      return;
    }
    // 重排刚换过控制器、PageView 还没挂上就点了：`jumpToPage` 会撞 assert，
    // 只能换一个带新初始页的控制器，由下一帧的 PageView 认领。
    setState(_installPageController);
    _settle();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(
        math.max(1, constraints.maxWidth - widget.padding.horizontal),
        math.max(1, constraints.maxHeight - widget.padding.vertical),
      );
      if (_viewport != viewport ||
          _slots.any((slot) => slot.stale && _measurable(slot))) {
        _scheduleMeasure(viewport);
      }
      final active = _active;
      return Stack(
        children: <Widget>[
          // 测量层：每章照正文宽度各排一遍，尺寸恒为 0、不绘制、不参与命中测试。
          //
          // 每一层都要带 key：窗口挪动会增删测量层，而 Stack 的孩子没有 key 时按
          // 下标配对——正文层会被拿去复用某个测量层的 element，`PageView` 连同它的
          // 滚动位置一起重建，画面当场闪回 `initialPage` 那一页。
          for (final slot in _slots)
            if (_measurable(slot))
              Positioned(
                key: ValueKey<String>('reader-measure-${slot.sortNum}'),
                width: 0,
                height: 0,
                child: ReaderMeasureBox(
                  width: viewport.width,
                  child: _column(slot, slot.measureKey),
                ),
              ),
          if (active != null && active.renderable)
            Positioned.fill(
              key: const ValueKey<String>('reader-content'),
              child: ReaderTapZoneLayer(
                // 滚动模式没有翻页热区，三块区域都用来切换工具栏。
                onPrevious: widget.paged
                    ? () => _turn(false)
                    : widget.onTapCenter,
                onNext: widget.paged ? () => _turn(true) : widget.onTapCenter,
                onToggleChrome: widget.onTapCenter,
                child: widget.paged
                    ? _pagedContent(viewport)
                    : _scrollingContent(active),
              ),
            ),
        ],
      );
    },
  );

  Widget _column(_ChapterSlot slot, Key? key) => Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: slot.blockWidgets,
  );

  Widget _scrollingContent(_ChapterSlot slot) => SingleChildScrollView(
    controller: _scrollController,
    padding: widget.padding,
    child: _column(slot, null),
  );

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
            return _pageContent(located.$1, viewport, located.$2);
          },
        ),
      );

  Widget _pageContent(_ChapterSlot slot, Size viewport, int index) {
    final geometry = slot.geometry;
    if (geometry == null || !slot.renderable || index >= slot.pageCount) {
      return const SizedBox.shrink();
    }
    final top = slot.pageTops[index];
    // 页底一律裁到下一页的页顶，而不是裁满一屏：装不下的那一行行顶就在视口之内，
    // 按整屏画会把它的上半截留在页底，看着像最后一行印了两遍。
    final bottom = index + 1 < slot.pageCount
        ? slot.pageTops[index + 1]
        : math.min(top + viewport.height, geometry.height);
    final first = readerBlockIndexAtOffset(
      blockTops: geometry.blockTops,
      blockBottoms: geometry.blockBottoms,
      offset: top,
    );
    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: readerPageBodyKey(slot.sortNum, index),
          width: double.infinity,
          height: math.min(viewport.height, math.max(0, bottom - top)),
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (
                  var block = first;
                  block < slot.blockWidgets.length &&
                      geometry.blockTops[block] < bottom;
                  block++
                )
                  Positioned(
                    left: 0,
                    right: 0,
                    top: geometry.blockTops[block] - top,
                    child: slot.blockWidgets[block],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
