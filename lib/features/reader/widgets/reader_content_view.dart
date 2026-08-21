import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../reader_content_markup.dart';
import '../reader_content_style.dart';
import '../reader_engine.dart';
import '../reader_pagination.dart';
import 'reader_html_block.dart';

/// 正文位置上报。`page`/`pages` 从 1 开始，滚动模式恒为 0。
class ReaderContentPosition {
  const ReaderContentPosition({
    required this.locator,
    required this.progression,
    required this.page,
    required this.pages,
  });

  final String locator;
  final double progression;
  final int page;
  final int pages;
}

/// 某一页的绘制区域；高度就是该页实际占用的正文高度，末尾空白不在其内。
Key readerPageBodyKey(int index) => ValueKey<String>('reader-page-$index');

/// 原生正文视图。
///
/// 正文用 `HtmlWidget` 渲染，翻页与定位由 Flutter 侧完成：先把整章排在一个零尺寸的
/// 测量层里，读出每个块的纵向区间与每一行的行顶，再按视口高度切页；翻页模式的每一页
/// 只把落在该页区间的块按测量偏移摆进 `Stack` 并裁掉溢出，行的位置与测量层逐像素一致。
/// 排版/视口/图片尺寸变化都会重新测量，并把阅读位置钉回当前 locator。
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.blocks,
    required this.style,
    required this.paged,
    required this.padding,
    required this.restoreLocator,
    required this.restoreProgression,
    required this.onPosition,
    required this.onTapCenter,
    required this.onBoundary,
    required this.onFootnote,
    required this.onReady,
  });

  final List<NovelReaderBlock> blocks;
  final ReaderContentStyle style;
  final bool paged;

  /// 正文四周留白：翻页模式下上下留白作用在每一页上。
  final EdgeInsets padding;

  final String? restoreLocator;
  final double restoreProgression;

  final ValueChanged<ReaderContentPosition> onPosition;
  final VoidCallback onTapCenter;

  /// 首页再往前 / 末页再往后：交给上层翻章。
  final ValueChanged<bool> onBoundary;

  final ValueChanged<String> onFootnote;

  /// 首次测量并定位完成。
  final VoidCallback onReady;

  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

/// 一次测量的结果，坐标都相对正文顶部。
class _ReaderGeometry {
  const _ReaderGeometry({
    required this.blockTops,
    required this.blockBottoms,
    required this.breaks,
    required this.height,
  });

  final List<double> blockTops;
  final List<double> blockBottoms;

  /// 升序去重的可断处：块边界与每个段落除首行以外的行顶。
  final List<double> breaks;
  final double height;
}

class _ReaderContentViewState extends State<ReaderContentView> {
  final GlobalKey _measureKey = GlobalKey();

  List<Widget> _blockWidgets = const <Widget>[];
  _ReaderGeometry? _geometry;
  List<double> _pageTops = const <double>[0];
  Size _viewport = Size.zero;

  ScrollController? _scrollController;
  PageController? _pageController;

  /// 最近一次重排钉下的滚动偏移，控制器还没挂载时的上报靠它。
  double _installedOffset = 0;

  bool _measureScheduled = false;
  bool _remeasure = false;
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
    _rebuildBlocks();
  }

  @override
  void didUpdateWidget(ReaderContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final blocksChanged = !identical(oldWidget.blocks, widget.blocks);
    if (blocksChanged) {
      _geometry = null;
      _pageTops = const <double>[0];
      _locator = '';
      _progression = 0;
      _pageIndex = 0;
      _ready = false;
    }
    if (blocksChanged || oldWidget.style != widget.style) {
      _rebuildBlocks();
      _measureAttempts = 0;
      _remeasure = true;
    } else if (oldWidget.paged != widget.paged ||
        oldWidget.padding != widget.padding) {
      _measureAttempts = 0;
      _remeasure = true;
    }
  }

  @override
  void dispose() {
    _trailingReport?.cancel();
    _scrollController?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _rebuildBlocks() {
    final markup = buildReaderBlockMarkup(widget.blocks, widget.style);
    _blockWidgets = <Widget>[
      for (var index = 0; index < markup.length; index++)
        _ReaderBlockBox(
          index: index,
          child: ReaderHtmlBlock(
            markup: markup[index],
            style: widget.style,
            applyParagraphSpacing: index + 1 < markup.length,
            onFootnote: widget.onFootnote,
            onLayoutChanged: _onBlockLayoutChanged,
          ),
        ),
    ];
  }

  void _onBlockLayoutChanged() {
    if (!mounted) return;
    setState(() {
      _measureAttempts = 0;
      _remeasure = true;
    });
  }

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
    final root = _measureKey.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize) {
      _retryMeasure(viewport);
      return;
    }
    final count = _blockWidgets.length;
    final tops = List<double>.filled(count, 0);
    final bottoms = List<double>.filled(count, 0);
    final breaks = <double>[];
    var measured = 0;
    void visit(RenderObject node) {
      if (node is _RenderReaderBlock) {
        if (!node.hasSize || node.index >= count) return;
        final top = node.localToGlobal(Offset.zero, ancestor: root).dy;
        tops[node.index] = top;
        bottoms[node.index] = top + node.size.height;
        measured++;
      }
      if (node is RenderParagraph) {
        if (node.hasSize) {
          _collectLineTops(
            node,
            node.localToGlobal(Offset.zero, ancestor: root).dy,
            breaks,
          );
        }
        return; // 段落内部只有占位子节点，行几何已经取到。
      }
      node.visitChildren(visit);
    }

    visit(root);
    if (measured != count) {
      // 还有块没排完（异步 build 的正文），再等一帧；重试有上限，免得空转掉帧。
      _retryMeasure(viewport);
      return;
    }

    breaks
      ..addAll(tops)
      ..addAll(bottoms)
      ..sort();
    final geometry = _ReaderGeometry(
      blockTops: tops,
      blockBottoms: bottoms,
      breaks: _dedupe(breaks),
      height: root.size.height,
    );
    final pageTops = widget.paged
        ? paginateReaderContent(
            contentHeight: geometry.height,
            pageHeight: viewport.height,
            breaks: geometry.breaks,
          )
        : const <double>[0];
    final offset = _anchorOffset(geometry, viewport);

    setState(() {
      _viewport = viewport;
      _measureAttempts = 0;
      _remeasure = false;
      _geometry = geometry;
      _pageTops = pageTops;
      _pageIndex = widget.paged
          ? readerPageIndexForOffset(pageTops, offset)
          : 0;
      _installControllers(offset);
    });

    _report(force: true);
    if (_ready) return;
    _ready = true;
    widget.onReady();
  }

  /// 行顶取 `includeLineSpacingTop`：切页落在行距里，不会削掉字。
  void _collectLineTops(
    RenderParagraph paragraph,
    double top,
    List<double> breaks,
  ) {
    final length = paragraph.text
        .toPlainText(includeSemanticsLabels: false)
        .length;
    if (length < 2) return;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: length),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingTop,
    );
    for (final box in boxes) {
      // 首行行顶就是块顶，块边界已经覆盖。
      if (box.top > 1) breaks.add(top + box.top);
    }
  }

  static List<double> _dedupe(List<double> sorted) {
    final result = <double>[];
    for (final value in sorted) {
      if (value <= 0) continue;
      if (result.isNotEmpty && value - result.last < 0.5) continue;
      result.add(value);
    }
    return result;
  }

  /// 重排后钉回当前 locator；首次进入才用上层给的进度。
  double _anchorOffset(_ReaderGeometry geometry, Size viewport) {
    final locator = _locator.isNotEmpty
        ? _locator
        : (widget.restoreLocator ?? '');
    if (locator.isNotEmpty && geometry.blockTops.isNotEmpty) {
      final index = findReaderBlockIndex(widget.blocks, locator);
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

  void _installControllers(double offset) {
    _scrollController?.dispose();
    _pageController?.dispose();
    _installedOffset = math.max(0, offset);
    if (widget.paged) {
      _scrollController = null;
      _pageController = PageController(initialPage: _pageIndex);
      return;
    }
    _pageController = null;
    // 控制器带着初始偏移新建，省掉「先挂载再 jumpTo」那一帧的跳动。
    _scrollController = ScrollController(initialScrollOffset: _installedOffset)
      ..addListener(_onScroll);
  }

  void _onScroll() => _report(force: false);

  /// 与旧 WebView 版本一致的 250ms 节流，尾巴上补一次，停下来的位置不会漏报。
  void _report({required bool force}) {
    final geometry = _geometry;
    if (geometry == null || !mounted) return;
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

    final offset = _contentOffset();
    final index = _locatorIndex(geometry, offset);
    if (index < widget.blocks.length) {
      _locator = widget.blocks[index].locator;
    }
    if (widget.paged) {
      _progression = _pageTops.length <= 1
          ? 0
          : _pageIndex / (_pageTops.length - 1);
    } else {
      final maxOffset = math.max(0, geometry.height - _viewport.height);
      _progression = maxOffset <= 0 ? 0 : (offset / maxOffset).clamp(0.0, 1.0);
    }
    widget.onPosition(
      ReaderContentPosition(
        locator: _locator,
        progression: _progression,
        page: widget.paged ? _pageIndex + 1 : 0,
        pages: widget.paged ? _pageTops.length : 0,
      ),
    );
  }

  /// 进度落在哪个块上。
  ///
  /// 翻页模式下页顶那个块常常是从上一页跨过来的：进度要记在本页第一个整块上，
  /// 否则按 locator 重开会退回上一页，报出去的位置也不再幂等。
  int _locatorIndex(_ReaderGeometry geometry, double offset) {
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

  double _contentOffset() {
    if (widget.paged) {
      return _pageIndex < _pageTops.length ? _pageTops[_pageIndex] : 0;
    }
    final controller = _scrollController;
    // 控制器挂载前（重排后紧跟的那次上报）只有刚钉下的偏移可用，读 0 会把定位打回章首。
    if (controller == null || !controller.hasClients) return _installedOffset;
    return math.max(0, controller.offset);
  }

  void _onTapUp(double dx, double width) {
    if (!widget.paged) {
      widget.onTapCenter();
      return;
    }
    if (dx <= width * 0.3) {
      _turn(false);
    } else if (dx >= width * 0.7) {
      _turn(true);
    } else {
      widget.onTapCenter();
    }
  }

  void _turn(bool next) {
    final controller = _pageController;
    final target = _pageIndex + (next ? 1 : -1);
    if (controller == null || target < 0 || target >= _pageTops.length) {
      widget.onBoundary(next);
      return;
    }
    // 直接跳页而不是动画：动画期间 PageView 的拖拽识别器会抢下一次点按（原本用来
    // 停住惯性滚动），连点翻页就会丢一次。滑动翻页仍走 PageView 自己的动画。
    _pageIndex = target;
    if (controller.hasClients) {
      controller.jumpToPage(target);
    } else {
      // 重排刚换过控制器、PageView 还没挂上就点了：`jumpToPage` 会撞 assert，
      // 只能换一个带新初始页的控制器，由下一帧的 PageView 认领。
      setState(() => _installControllers(_pageTops[target]));
    }
    _report(force: true);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(
        math.max(1, constraints.maxWidth - widget.padding.horizontal),
        math.max(1, constraints.maxHeight - widget.padding.vertical),
      );
      if (_remeasure || _geometry == null || _viewport != viewport) {
        _scheduleMeasure(viewport);
      }
      final geometry = _geometry;
      return Stack(
        children: <Widget>[
          // 测量层：照正文宽度排整章，但尺寸恒为 0、不绘制、不参与命中测试。
          Positioned(
            width: 0,
            height: 0,
            child: _ReaderMeasureBox(
              width: viewport.width,
              child: _column(_measureKey),
            ),
          ),
          if (geometry != null &&
              geometry.blockTops.length == _blockWidgets.length)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) =>
                    _onTapUp(details.localPosition.dx, constraints.maxWidth),
                child: widget.paged
                    ? _pagedContent(geometry, viewport)
                    : _scrollingContent(),
              ),
            ),
        ],
      );
    },
  );

  Widget _column(Key? key) => Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _blockWidgets,
  );

  Widget _scrollingContent() => SingleChildScrollView(
    controller: _scrollController,
    padding: widget.padding,
    child: _column(null),
  );

  Widget _pagedContent(_ReaderGeometry geometry, Size viewport) =>
      PageView.builder(
        controller: _pageController,
        itemCount: _pageTops.length,
        onPageChanged: (index) {
          _pageIndex = index;
          _report(force: true);
        },
        itemBuilder: (context, index) =>
            _pageContent(geometry, viewport, index),
      );

  Widget _pageContent(_ReaderGeometry geometry, Size viewport, int index) {
    final top = _pageTops[index];
    // 页底一律裁到下一页的页顶，而不是裁满一屏：装不下的那一行行顶就在视口之内，
    // 按整屏画会把它的上半截留在页底，看着像最后一行印了两遍。
    final bottom = index + 1 < _pageTops.length
        ? _pageTops[index + 1]
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
          key: readerPageBodyKey(index),
          width: double.infinity,
          height: math.min(viewport.height, math.max(0, bottom - top)),
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (
                  var block = first;
                  block < _blockWidgets.length &&
                      geometry.blockTops[block] < bottom;
                  block++
                )
                  Positioned(
                    left: 0,
                    right: 0,
                    top: geometry.blockTops[block] - top,
                    child: _blockWidgets[block],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 标出一个正文块的边界，测量时靠它把渲染树切回块序列。
class _ReaderBlockBox extends SingleChildRenderObjectWidget {
  const _ReaderBlockBox({required this.index, required Widget super.child});

  final int index;

  @override
  _RenderReaderBlock createRenderObject(BuildContext context) =>
      _RenderReaderBlock(index);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReaderBlock renderObject,
  ) => renderObject.index = index;
}

class _RenderReaderBlock extends RenderProxyBox {
  _RenderReaderBlock(this.index);

  int index;
}

/// 测量容器：给子节点正文宽度与无限高度，自身恒为零尺寸且不绘制。
class _ReaderMeasureBox extends SingleChildRenderObjectWidget {
  const _ReaderMeasureBox({required this.width, required Widget super.child});

  final double width;

  @override
  _RenderReaderMeasure createRenderObject(BuildContext context) =>
      _RenderReaderMeasure(width);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReaderMeasure renderObject,
  ) => renderObject.width = width;
}

class _RenderReaderMeasure extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderReaderMeasure(double width) : _width = width;

  double _width;

  double get width => _width;

  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void performLayout() {
    child?.layout(
      BoxConstraints(minWidth: _width, maxWidth: _width),
      parentUsesSize: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}
