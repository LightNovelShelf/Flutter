import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 把超过 [maxHeight] 的内容裁到预算高度，底部 [fadeExtent] 高的区间渐隐。
///
/// 行高不固定（ruby 注音、着重号、异常字号会撑高行盒）时裁切点必然落在行内，
/// 渐隐让截断看起来是内容延续而不是硬切字形。
class FadeClampBox extends SingleChildRenderObjectWidget {
  const FadeClampBox({
    super.key,
    required this.maxHeight,
    required this.fadeExtent,
    this.onMeasured,
    required Widget super.child,
  });

  final double maxHeight;
  final double fadeExtent;

  /// 内容未裁剪时的真实高度，布局结束后的帧末回调。
  final ValueChanged<double>? onMeasured;

  @override
  RenderFadeClampBox createRenderObject(BuildContext context) =>
      RenderFadeClampBox(
        maxHeight: maxHeight,
        fadeExtent: fadeExtent,
        onMeasured: onMeasured,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFadeClampBox renderObject,
  ) {
    renderObject
      ..maxHeight = maxHeight
      ..fadeExtent = fadeExtent
      ..onMeasured = onMeasured;
  }
}

class RenderFadeClampBox extends RenderProxyBox {
  RenderFadeClampBox({
    required double maxHeight,
    required double fadeExtent,
    this.onMeasured,
  }) : _maxHeight = maxHeight,
       _fadeExtent = fadeExtent;

  double _maxHeight;
  double _fadeExtent;
  ValueChanged<double>? onMeasured;
  double _contentHeight = 0;
  double? _measured;

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();
  final LayerHandle<ShaderMaskLayer> _maskLayer =
      LayerHandle<ShaderMaskLayer>();

  double get maxHeight => _maxHeight;

  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  double get fadeExtent => _fadeExtent;

  set fadeExtent(double value) {
    if (value == _fadeExtent) return;
    _fadeExtent = value;
    markNeedsPaint();
  }

  // 推给 pushClipRect 的裁剪要走图层，否则内部的遮罩图层会截断画布上的裁剪状态。
  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.min(super.computeMinIntrinsicHeight(width), _maxHeight);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.min(super.computeMaxIntrinsicHeight(width), _maxHeight);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return computeSizeForNoChild(constraints);
    final size = child.getDryLayout(_contentConstraints(constraints));
    return constraints.constrain(
      Size(size.width, math.min(size.height, _maxHeight)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = computeSizeForNoChild(constraints);
      return;
    }
    child.layout(_contentConstraints(constraints), parentUsesSize: true);
    _contentHeight = child.size.height;
    size = constraints.constrain(
      Size(child.size.width, math.min(_contentHeight, _maxHeight)),
    );
    _report(_contentHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      _clipLayer.layer = null;
      _maskLayer.layer = null;
      return;
    }
    final fade = math.min(_fadeExtent, size.height);
    if (_contentHeight <= size.height + 0.5 || fade <= 0) {
      _clipLayer.layer = null;
      _maskLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (clipped, clippedOffset) =>
          _paintFaded(clipped, clippedOffset, child, fade),
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _maskLayer.layer = null;
    super.dispose();
  }

  BoxConstraints _contentConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      );

  void _paintFaded(
    PaintingContext context,
    Offset offset,
    RenderBox child,
    double fade,
  ) {
    // 渐变按 RenderShaderMask 的约定给局部坐标，maskRect 给绘制坐标。
    final mask = _maskLayer.layer ??= ShaderMaskLayer();
    mask
      ..shader = ui.Gradient.linear(
        Offset(0, size.height - fade),
        Offset(0, size.height),
        const <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)],
      )
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      mask,
      (inner, innerOffset) => inner.paintChild(child, innerOffset),
      offset,
    );
  }

  void _report(double height) {
    if (onMeasured == null) return;
    if (_measured != null && (_measured! - height).abs() < 0.5) return;
    _measured = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!attached) return;
      onMeasured?.call(height);
    });
  }
}
