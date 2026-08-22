import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 分页测量层：把整章分片排在一个零尺寸容器里，逐片从渲染树读回块度量，再拼成全章几何。

/// 一个正文块的度量：块高与块内除首行以外的行顶，行顶相对块顶。
class ReaderBlockMetrics {
  const ReaderBlockMetrics({required this.height, required this.lineTops});

  final double height;

  /// 升序，可作切页点的行顶。首行行顶等于块顶，由块边界覆盖。
  final List<double> lineTops;
}

/// 一次测量的结果，坐标都相对正文顶部。
class ReaderGeometry {
  const ReaderGeometry({
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

/// 逐片测量的累积器：块高前缀和给出块区间，块内行顶平移后并入可断处。
///
/// 块高互不影响（测量层按固定正文宽度纵向堆叠），所以分片测量与整章一次测量结果相同。
class ReaderGeometryBuilder {
  final List<ReaderBlockMetrics> _blocks = <ReaderBlockMetrics>[];

  int get measured => _blocks.length;

  void add(Iterable<ReaderBlockMetrics> metrics) => _blocks.addAll(metrics);

  /// 图片回填真实尺寸后改写单块度量，高度未变则返回 false，几何不必重建。
  bool patch(int index, ReaderBlockMetrics metrics) {
    if (index < 0 || index >= _blocks.length) return false;
    final previous = _blocks[index];
    _blocks[index] = metrics;
    return (previous.height - metrics.height).abs() > 0.5;
  }

  ReaderGeometry build() {
    final count = _blocks.length;
    final tops = List<double>.filled(count, 0);
    final bottoms = List<double>.filled(count, 0);
    final breaks = <double>[];
    var top = 0.0;
    for (var index = 0; index < count; index++) {
      final block = _blocks[index];
      tops[index] = top;
      top += block.height;
      bottoms[index] = top;
      for (final lineTop in block.lineTops) {
        breaks.add(tops[index] + lineTop);
      }
    }
    breaks
      ..addAll(tops)
      ..addAll(bottoms)
      ..sort();
    return ReaderGeometry(
      blockTops: tops,
      blockBottoms: bottoms,
      breaks: _dedupe(breaks),
      height: top,
    );
  }
}

/// 从测量层的渲染树读回 [start, start + count) 这段块的度量；
/// 还有块没排完（异步 build 的正文）时返回 null，调用方再等一帧。
List<ReaderBlockMetrics>? collectReaderBlockMetrics(
  RenderBox root,
  int start,
  int count,
) {
  final metrics = List<ReaderBlockMetrics?>.filled(count, null);
  var measured = 0;

  void collectBlock(RenderReaderBlock block) {
    final lineTops = <double>[];
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        if (node.hasSize) {
          _collectLineTops(
            node,
            node.localToGlobal(Offset.zero, ancestor: block).dy,
            lineTops,
          );
        }
        return; // 段落内部只有占位子节点，行几何已经取到。
      }
      node.visitChildren(visit);
    }

    block.visitChildren(visit);
    lineTops.sort();
    metrics[block.index - start] = ReaderBlockMetrics(
      height: block.size.height,
      lineTops: _dedupe(lineTops),
    );
    measured++;
  }

  void scan(RenderObject node) {
    if (node is RenderReaderBlock) {
      final index = node.index;
      if (node.hasSize && index >= start && index < start + count) {
        collectBlock(node);
      }
      return;
    }
    node.visitChildren(scan);
  }

  scan(root);
  if (measured != count) return null;
  return metrics.cast<ReaderBlockMetrics>();
}

/// 行顶取 `includeLineSpacingTop`，切页落在行距内而不截断字形。
void _collectLineTops(
  RenderParagraph paragraph,
  double top,
  List<double> lineTops,
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
    if (box.top > 1) lineTops.add(top + box.top);
  }
}

List<double> _dedupe(List<double> sorted) {
  final result = <double>[];
  for (final value in sorted) {
    if (value <= 0) continue;
    if (result.isNotEmpty && value - result.last < 0.5) continue;
    result.add(value);
  }
  return result;
}

/// 标出一个正文块的边界，测量时靠它把渲染树切回块序列。
class ReaderBlockBox extends SingleChildRenderObjectWidget {
  const ReaderBlockBox({
    super.key,
    required this.index,
    required Widget super.child,
  });

  final int index;

  @override
  RenderReaderBlock createRenderObject(BuildContext context) =>
      RenderReaderBlock(index);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderBlock renderObject,
  ) => renderObject.index = index;
}

class RenderReaderBlock extends RenderProxyBox {
  RenderReaderBlock(this.index);

  int index;
}

/// 测量容器：给子节点正文宽度与无限高度，自身恒为零尺寸且不绘制。
class ReaderMeasureBox extends SingleChildRenderObjectWidget {
  const ReaderMeasureBox({
    super.key,
    required this.width,
    required Widget super.child,
  });

  final double width;

  @override
  RenderReaderMeasure createRenderObject(BuildContext context) =>
      RenderReaderMeasure(width);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderMeasure renderObject,
  ) => renderObject.width = width;
}

class RenderReaderMeasure extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  RenderReaderMeasure(double width) : _width = width;

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
