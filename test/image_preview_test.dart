import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/image_preview.dart';

/// 全屏图片预览的过渡不变量：进入/退出都走动画（从来源矩形缩放而来），
/// 下拉超过阈值关闭，未达阈值弹回。
///
/// 图片永远加载不出来时 PhotoView 会一直转菊花，所以只能定量 `pump`，
/// 不能用 `pumpAndSettle`。
void main() {
  const String url = 'https://img.example/page.webp';
  const Rect source = Rect.fromLTWH(20, 40, 100, 150);

  Matrix4 previewTransform(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(imagePreviewTransformKey))
      .transform;

  /// z 轴不缩放，`getMaxScaleOnAxis` 恒为 1，只能读 x 轴。
  double previewScale(WidgetTester tester) =>
      previewTransform(tester).storage[0];

  Future<void> openPreview(WidgetTester tester, {Rect? sourceRect}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showImagePreview(context, url: url, sourceRect: sourceRect),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> finishTransition(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 400));

  testWidgets('从来源矩形逐帧放大，而不是直接铺满', (WidgetTester tester) async {
    await openPreview(tester, sourceRect: source);

    // 800x600 的测试屏幕上，100x150 的缩略图对应 0.25 的起始缩放。
    final double first = previewScale(tester);
    expect(first, lessThan(0.6));

    await tester.pump(const Duration(milliseconds: 100));
    final double middle = previewScale(tester);
    expect(middle, greaterThan(first));
    expect(middle, lessThan(1));

    await finishTransition(tester);
    expect(previewScale(tester), moreOrLessEquals(1, epsilon: 0.001));
  });

  testWidgets('无来源矩形时仍有淡入缩放过渡', (WidgetTester tester) async {
    await openPreview(tester);

    final double first = previewScale(tester);
    expect(first, lessThan(1));
    expect(first, greaterThan(0.85));

    await finishTransition(tester);
    expect(previewScale(tester), moreOrLessEquals(1, epsilon: 0.001));
  });

  testWidgets('关闭时反向缩回来源矩形', (WidgetTester tester) async {
    await openPreview(tester, sourceRect: source);
    await finishTransition(tester);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(previewScale(tester), lessThan(1));

    await finishTransition(tester);
    expect(find.byTooltip('关闭'), findsNothing);
  });

  testWidgets('下拉不到阈值弹回原位', (WidgetTester tester) async {
    await openPreview(tester);
    await finishTransition(tester);

    await tester.drag(
      find.byKey(imagePreviewTransformKey),
      const Offset(0, 40),
    );
    await tester.pump();
    expect(previewTransform(tester).getTranslation().y, isNot(0));
    expect(previewScale(tester), lessThan(1));

    await finishTransition(tester);
    expect(previewTransform(tester).getTranslation().y, moreOrLessEquals(0));
    expect(previewScale(tester), moreOrLessEquals(1, epsilon: 0.001));
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('下拉超过阈值直接关闭', (WidgetTester tester) async {
    await openPreview(tester);
    await finishTransition(tester);

    await tester.drag(
      find.byKey(imagePreviewTransformKey),
      const Offset(0, 200),
    );
    await tester.pump();
    await finishTransition(tester);

    expect(find.byTooltip('关闭'), findsNothing);
  });
}
