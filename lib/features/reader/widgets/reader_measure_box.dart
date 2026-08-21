import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 分页测量层：把整章排在一个零尺寸容器里，再从渲染树读回块边界与可断处。

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

/// 从测量层的渲染树读回 [blockCount] 个块的区间与可断处；
/// 还有块没排完（异步 build 的正文）时返回 null，调用方再等一帧。
ReaderGeometry? collectReaderGeometry(RenderBox root, int blockCount) {
  final tops = List<double>.filled(blockCount, 0);
  final bottoms = List<double>.filled(blockCount, 0);
  final breaks = <double>[];
  var measured = 0;
  void visit(RenderObject node) {
    if (node is RenderReaderBlock) {
      if (!node.hasSize || node.index >= blockCount) return;
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
  if (measured != blockCount) return null;

  breaks
    ..addAll(tops)
    ..addAll(bottoms)
    ..sort();
  return ReaderGeometry(
    blockTops: tops,
    blockBottoms: bottoms,
    breaks: _dedupe(breaks),
    height: root.size.height,
  );
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
