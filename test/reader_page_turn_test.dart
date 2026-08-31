import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/reader/reader_page_turn.dart';

Future<PageController> _pumpPages(WidgetTester tester) async {
  final controller = PageController();
  await tester.pumpWidget(
    MaterialApp(
      home: PageView(
        controller: controller,
        children: const <Widget>[SizedBox(), SizedBox()],
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('无动画直接切换目标页', (tester) async {
    final controller = await _pumpPages(tester);
    addTearDown(controller.dispose);

    turnReaderPage(controller, 1, ReaderPageTurnAnimation.none);
    await tester.pump();

    expect(controller.page, 1);
  });

  testWidgets('滑动动画在时长内平滑切换目标页', (tester) async {
    final controller = await _pumpPages(tester);
    addTearDown(controller.dispose);

    turnReaderPage(controller, 1, ReaderPageTurnAnimation.slide);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.page, greaterThan(0));
    expect(controller.page, lessThan(1));

    await tester.pump(readerPageTurnDuration);
    expect(controller.page, 1);
  });
}
