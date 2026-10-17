import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/widgets/reader_frame.dart';

void main() {
  const channel = MethodChannel('app.lightnovel.shelf/battery');

  Future<void> pumpFrame(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ReaderFrameInfo(
                title: '第一章 开端',
                foregroundColor: Colors.black,
                infoVisible: true,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('左下角显示电量与时间，左上角显示章节名', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => <String, Object?>{'level': 76, 'charging': false},
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await pumpFrame(tester);

    final title = tester.getRect(find.text('第一章 开端'));
    expect(title.left, 16);
    expect(title.top, greaterThanOrEqualTo(ReaderFrameInfo.edgeGap));
    expect(
      title.bottom,
      lessThanOrEqualTo(ReaderFrameInfo.edgeGap + ReaderFrameInfo.rowExtent),
    );
    expect(find.text('76%'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reader-clock')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('76%')).dy,
      greaterThan(800 - ReaderFrameInfo.footerExtent),
    );
  });

  testWidgets('读不到电量时只显示时间', (tester) async {
    await pumpFrame(tester);

    expect(find.textContaining('%'), findsNothing);
    expect(find.byKey(const ValueKey<String>('reader-clock')), findsOneWidget);
  });
}
