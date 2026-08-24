import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/widgets/reader_chrome.dart';

Widget buildChrome({
  bool visible = true,
  int currentChapter = 2,
  int totalChapters = 10,
  List<String> chapterTitles = const <String>[],
  bool nightMode = false,
  bool nightModeLocked = false,
  ValueChanged<int>? onChapterSelected,
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
      currentChapter: currentChapter,
      totalChapters: totalChapters,
      chapterTitles: chapterTitles,
      onOpenChapters: onOpenChapters ?? () {},
      nightMode: nightMode,
      onToggleNightMode: nightModeLocked ? null : (onToggleNightMode ?? () {}),
      onOpenSettings: onOpenSettings ?? () {},
      onDismiss: () {},
      onPreviousChapter: () {},
      onNextChapter: () {},
      onChapterSelected: onChapterSelected,
    ),
  ),
);

double sliderValue(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

void main() {
  testWidgets('拖动章节进度条：气泡给出原始标题，松手才选中目标章节', (tester) async {
    int? selectedChapter;

    await tester.pumpWidget(
      buildChrome(
        chapterTitles: <String>[
          for (var chapter = 1; chapter <= 10; chapter++)
            '第$chapter卷 标题$chapter',
        ],
        onChapterSelected: (chapter) => selectedChapter = chapter,
      ),
    );

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(selectedChapter, isNull);
    expect(sliderValue(tester), 10);
    // 标题原样显示，不做清洗改写：第 10 卷不能被说成第 10 章。
    expect(find.text('第10卷 标题10'), findsOneWidget);
    expect(tester.getRect(find.text('第10卷 标题10')).bottom, lessThan(slider.top));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedChapter, 10);
    expect(find.text('第10卷 标题10'), findsNothing);
  });

  testWidgets('章节标题缺失时气泡退回章号', (tester) async {
    await tester.pumpWidget(buildChrome(onChapterSelected: (_) {}));

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump(const Duration(milliseconds: 140));

    expect(find.text('第10章'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('选章没能生效时滑块退回当前章节，不停在目标章节', (tester) async {
    await tester.pumpWidget(buildChrome(onChapterSelected: (_) {}));

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 外部 currentChapter 没变（打开失败/被抢占），滑块不能继续指向第 10 章。
    expect(sliderValue(tester), 2);
  });

  testWidgets('拖动中工具栏收起：预览一并清掉', (tester) async {
    await tester.pumpWidget(buildChrome(onChapterSelected: (_) {}));

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text('第10章'), findsOneWidget);

    await tester.pumpWidget(
      buildChrome(visible: false, onChapterSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(sliderValue(tester), 2);
    expect(find.text('第10章'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('单章书不渲染章节滑杆', (tester) async {
    await tester.pumpWidget(
      buildChrome(
        currentChapter: 1,
        totalChapters: 1,
        onChapterSelected: (_) {},
      ),
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
