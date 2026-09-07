import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ShaderMaskLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/fade_clamp_box.dart';

const double _budget = 40;
const double _fade = 10;

Future<void> _pump(
  WidgetTester tester,
  double contentHeight, {
  ValueChanged<double>? onMeasured,
}) => tester.pumpWidget(
  MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: FadeClampBox(
        maxHeight: _budget,
        fadeExtent: _fade,
        onMeasured: onMeasured,
        child: SizedBox(width: 20, height: contentHeight),
      ),
    ),
  ),
);

void main() {
  testWidgets('超高内容裁到预算高度，底部渐隐遮罩盖住裁切处', (tester) async {
    await _pump(tester, 200);

    expect(tester.getSize(find.byType(FadeClampBox)).height, _budget);
    final mask = tester.layers.whereType<ShaderMaskLayer>().single;
    expect(mask.maskRect, const Rect.fromLTWH(0, 0, 20, _budget));
    expect(mask.blendMode, BlendMode.dstIn);
  });

  testWidgets('未超预算的内容不裁剪也不渐隐', (tester) async {
    await _pump(tester, 24);

    expect(tester.getSize(find.byType(FadeClampBox)).height, 24);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
  });

  testWidgets('回调给出未裁剪的真实高度', (tester) async {
    final heights = <double>[];
    await _pump(tester, 137, onMeasured: heights.add);
    await tester.pump();

    expect(heights, <double>[137]);
  });
}
