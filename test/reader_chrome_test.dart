import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/widgets/reader_chrome.dart';

Widget buildChrome({
  bool visible = true,
  int currentPage = 2,
  int totalPages = 10,
  bool nightMode = false,
  bool nightModeLocked = false,
  ValueChanged<int>? onSeekPage,
  VoidCallback? onOpenChapters,
  VoidCallback? onToggleNightMode,
  VoidCallback? onOpenSettings,
}) => MaterialApp(
  home: Scaffold(
    body: ReaderChrome(
      visible: visible,
      title: '测试章节',
      backgroundColor: const Color(0xFFE0C4A1),
      foregroundColor: const Color(0xFF2A2318),
      currentChapter: 2,
      totalChapters: 10,
      currentPage: currentPage,
      totalPages: totalPages,
      onOpenChapters: onOpenChapters ?? () {},
      nightMode: nightMode,
      onToggleNightMode: nightModeLocked ? null : (onToggleNightMode ?? () {}),
      onOpenSettings: onOpenSettings ?? () {},
      onDismiss: () {},
      onPreviousChapter: () {},
      onNextChapter: () {},
      onSeekPage: onSeekPage,
    ),
  ),
);

double sliderValue(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

void main() {
  testWidgets('拖动进度条：气泡给出章内页码与进度，松手才跳页', (tester) async {
    int? seeked;

    await tester.pumpWidget(buildChrome(onSeekPage: (page) => seeked = page));

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(seeked, isNull);
    expect(sliderValue(tester), 10);
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    expect(tester.getRect(find.text('10 / 10')).bottom, lessThan(slider.top));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(seeked, 10);
    expect(find.text('10 / 10'), findsNothing);
  });

  testWidgets('跳页没能生效时滑块退回当前页，不停在目标页', (tester) async {
    await tester.pumpWidget(buildChrome(onSeekPage: (_) {}));

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 外部 currentPage 没变（跳转失败/被抢占），滑块不能继续指向第 10 页。
    expect(sliderValue(tester), 2);
  });

  testWidgets('拖动中工具栏收起：预览一并清掉', (tester) async {
    await tester.pumpWidget(buildChrome(onSeekPage: (_) {}));

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text('10 / 10'), findsOneWidget);

    await tester.pumpWidget(buildChrome(visible: false, onSeekPage: (_) {}));
    await tester.pumpAndSettle();

    expect(sliderValue(tester), 2);
    expect(find.text('10 / 10'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('滚动模式没有页码时不渲染滑杆', (tester) async {
    await tester.pumpWidget(
      buildChrome(currentPage: 0, totalPages: 0, onSeekPage: (_) {}),
    );

    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('目录、夜间和设置在底部菜单，读屏也能激活', (tester) async {
    var chaptersOpened = false;
    var nightModeToggled = false;
    var settingsOpened = false;
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      buildChrome(
        nightMode: true,
        onOpenChapters: () => chaptersOpened = true,
        onToggleNightMode: () => nightModeToggled = true,
        onOpenSettings: () => settingsOpened = true,
      ),
    );

    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('夜间'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    // 菜单在滑杆下面。
    expect(
      tester.getCenter(find.byIcon(Icons.list_alt_rounded)).dy,
      greaterThan(tester.getCenter(find.byType(Slider)).dy),
    );

    await tester.tap(find.text('目录'));
    await tester.tap(find.text('设置'));
    expect(chaptersOpened, isTrue);
    expect(settingsOpened, isTrue);

    // 语义节点必须带点击动作，否则 TalkBack 双击点不动。
    final night = tester.getSemantics(find.bySemanticsLabel('夜间模式'));
    expect(night.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(night.getSemanticsData().flagsCollection.isToggled, Tristate.isTrue);
    tester.semantics.performAction(
      find.semantics.byLabel('夜间模式'),
      SemanticsAction.tap,
    );
    await tester.pump();
    expect(nightModeToggled, isTrue);

    handle.dispose();
  });
  testWidgets('不许切主题时夜间按钮置灰点不动', (tester) async {
    await tester.pumpWidget(buildChrome(nightModeLocked: true));

    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text('夜间'), matching: find.byType(TextButton)),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('夜间'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
