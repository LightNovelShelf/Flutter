import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/reader/widgets/reader_page_turner.dart';

class _Harness {
  _Harness(this.animation, {this.reverse = false, this.spread = false});

  final ReaderPageTurnAnimation animation;
  final bool reverse;
  final bool spread;
  final ReaderPageTurnController controller = ReaderPageTurnController();
  final List<int> changes = <int>[];
  final List<bool> boundaries = <bool>[];
  int starts = 0;
  int ends = 0;

  Widget build() => MaterialApp(
    home: ReaderPageTurner(
      controller: controller,
      itemCount: 3,
      animation: animation,
      reverse: reverse,
      isSpread: spread ? (_) => true : null,
      onPageChanged: changes.add,
      onTurnStart: () => starts++,
      onTurnEnd: () => ends++,
      onBoundary: boundaries.add,
      itemBuilder: (context, index) =>
          SizedBox.expand(key: ValueKey<int>(index), child: Text('页$index')),
    ),
  );
}

Future<_Harness> _pump(
  WidgetTester tester,
  ReaderPageTurnAnimation animation, {
  bool reverse = false,
  bool spread = false,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = _Harness(animation, reverse: reverse, spread: spread);
  await tester.pumpWidget(harness.build());
  return harness;
}

double? _left(WidgetTester tester, int index) {
  final finder = find.byKey(ValueKey<int>(index));
  if (finder.evaluate().isEmpty) return null;
  return tester.getTopLeft(finder.first).dx;
}

void main() {
  testWidgets('无动画：控制器翻页立即换页', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.none);

    harness.controller.animateToPage(1);
    expect(harness.controller.page, 1);
    expect(harness.changes, <int>[1]);
    await tester.pump();

    expect(_left(tester, 1), 0);
    expect(_left(tester, 0), isNull);
    expect((harness.starts, harness.ends), (1, 1));
  });

  testWidgets('无动画：滑动只换页，不跟手也不播放过渡', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.none);

    final gesture = await tester.startGesture(const Offset(600, 300));
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(_left(tester, 0), 0);
    expect(_left(tester, 1), isNull);

    await gesture.up();
    await tester.pump();
    expect(harness.controller.page, 1);
    expect(_left(tester, 1), 0);
    expect(_left(tester, 0), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('平移：控制器翻页在时长内平滑过渡', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.slide);

    harness.controller.animateToPage(1);
    expect(harness.controller.page, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_left(tester, 0), lessThan(0));
    expect(_left(tester, 1), greaterThan(0));
    expect(_left(tester, 1), lessThan(800));

    await tester.pumpAndSettle();
    expect(_left(tester, 1), 0);
    expect(_left(tester, 0), isNull);
    expect((harness.starts, harness.ends), (1, 1));
  });

  testWidgets('平移：拖动时两页跟手，松手后落到下一页', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.slide);

    final gesture = await tester.startGesture(const Offset(600, 300));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    final first = _left(tester, 0)!;
    expect(first, lessThan(-150));
    expect(_left(tester, 1), closeTo(first + 800, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.controller.page, 1);
    expect(_left(tester, 1), 0);
  });

  testWidgets('平移：拖得太短会弹回原页', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.slide);

    await tester.timedDrag(
      find.byType(ReaderPageTurner),
      const Offset(-60, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(harness.controller.page, 0);
    expect(harness.changes, isEmpty);
    expect(_left(tester, 0), 0);
  });

  testWidgets('覆盖：下一页不动，当前页盖在上面滑走', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.cover);

    final gesture = await tester.startGesture(const Offset(600, 300));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(_left(tester, 1), 0);
    expect(_left(tester, 0), lessThan(-150));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.controller.page, 1);
  });

  testWidgets('仿真：单页卷角翻页，落定后只剩新页', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.simulation);

    harness.controller.animateToPage(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey<int>(0)), findsWidgets);
    expect(find.byKey(const ValueKey<int>(1)), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<int>(0)), findsNothing);
    expect(_left(tester, 1), 0);

    harness.controller.animateToPage(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(harness.controller.page, 0);
  });

  testWidgets('仿真：双页像书本一样只卷右栏，背面是下一屏', (tester) async {
    final harness = await _pump(
      tester,
      ReaderPageTurnAnimation.simulation,
      spread: true,
    );

    final gesture = await tester.startGesture(const Offset(780, 580));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-200, -20));
    await tester.pump();
    expect(find.byKey(const ValueKey<int>(1)), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.controller.page, 1);
    expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);
  });

  testWidgets('在最后一页继续往后滑交给上层', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.slide);
    harness.controller.jumpToPage(2);
    await tester.pump();

    await tester.fling(
      find.byType(ReaderPageTurner),
      const Offset(-300, 0),
      1500,
    );
    await tester.pumpAndSettle();

    expect(harness.controller.page, 2);
    expect(harness.boundaries, <bool>[true]);
  });

  testWidgets('右起时往右滑是下一页', (tester) async {
    final harness = await _pump(
      tester,
      ReaderPageTurnAnimation.none,
      reverse: true,
    );

    await tester.fling(
      find.byType(ReaderPageTurner),
      const Offset(300, 0),
      1500,
    );
    await tester.pumpAndSettle();

    expect(harness.controller.page, 1);
  });

  testWidgets('翻页动画中途再翻：先落定上一次，再接着翻', (tester) async {
    final harness = await _pump(tester, ReaderPageTurnAnimation.slide);

    harness.controller.animateToPage(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    harness.controller.animateToPage(2);
    await tester.pumpAndSettle();

    expect(harness.controller.page, 2);
    expect(harness.changes, <int>[1, 2]);
    expect(harness.starts, harness.ends);
  });
}
