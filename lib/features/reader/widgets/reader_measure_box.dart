import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 分页测量层的渲染对象：把整章排在一个零尺寸容器里，再从渲染树读回块边界。

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
