import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/widgets/reader_tap_zone.dart';

/// 小说分页、漫画分页、漫画连续三种热区的翻页方向。
void main() {
  const size = Size(300, 600);

  Future<List<String>> tapAt(
    WidgetTester tester,
    Offset position, {
    Axis axis = Axis.horizontal,
    bool reversed = false,
    bool withChild = false,
  }) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: ReaderTapZoneLayer(
              axis: axis,
              reversed: reversed,
              onPrevious: () => events.add('previous'),
              onNext: () => events.add('next'),
              onToggleChrome: () => events.add('chrome'),
              child: withChild ? const ColoredBox(color: Colors.white) : null,
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(ReaderTapZoneLayer));
    await tester.tapAt(origin + position);
    await tester.pump();
    return events;
  }

  testWidgets('横向：左 30% 上一页、右 30% 下一页、中间切换工具栏', (tester) async {
    expect(await tapAt(tester, const Offset(30, 300)), <String>['previous']);
    expect(await tapAt(tester, const Offset(280, 300)), <String>['next']);
    expect(await tapAt(tester, const Offset(150, 300)), <String>['chrome']);
  });

  testWidgets('横向反向阅读时左右对调', (tester) async {
    expect(
      await tapAt(tester, const Offset(30, 300), reversed: true),
      <String>['next'],
    );
    expect(
      await tapAt(tester, const Offset(280, 300), reversed: true),
      <String>['previous'],
    );
  });

  testWidgets('纵向连续模式按高度分区', (tester) async {
    expect(
      await tapAt(tester, const Offset(150, 30), axis: Axis.vertical),
      <String>['previous'],
    );
    expect(
      await tapAt(tester, const Offset(150, 560), axis: Axis.vertical),
      <String>['next'],
    );
    expect(
      await tapAt(tester, const Offset(150, 300), axis: Axis.vertical),
      <String>['chrome'],
    );
  });

  testWidgets('30%/70% 边界归中间区，避免误翻页', (tester) async {
    expect(await tapAt(tester, const Offset(91, 300)), <String>['chrome']);
    expect(await tapAt(tester, const Offset(209, 300)), <String>['chrome']);
  });

  testWidgets('包住正文时仍然接得到点击', (tester) async {
    expect(
      await tapAt(tester, const Offset(30, 300), withChild: true),
      <String>['previous'],
    );
  });
}
