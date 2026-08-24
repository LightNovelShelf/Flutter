import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/widgets/reader_chrome.dart';

void main() {
  testWidgets('拖动章节进度条后在松手时选中目标章节', (tester) async {
    int? selectedChapter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderChrome(
            visible: true,
            title: '测试章节',
            backgroundColor: const Color(0xFFE0C4A1),
            foregroundColor: const Color(0xFF2A2318),
            currentChapter: 2,
            totalChapters: 10,
            chapterTitles: <String>[
              for (var chapter = 1; chapter <= 10; chapter++)
                '第$chapter章 测试标题$chapter',
            ],
            onOpenChapters: () {},
            nightMode: false,
            onToggleNightMode: () {},
            onOpenSettings: () {},
            onDismiss: () {},
            onPreviousChapter: () {},
            onNextChapter: () {},
            onChapterSelected: (chapter) => selectedChapter = chapter,
          ),
        ),
      ),
    );

    expect(find.text('2 / 10'), findsNothing);

    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right, slider.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    expect(selectedChapter, isNull);
    expect(find.text('10 / 10'), findsNothing);
    expect(find.text('第10章：测试标题10'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    expect(
      tester.getRect(find.text('第10章：测试标题10')).bottom,
      lessThan(slider.top),
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedChapter, 10);
    expect(find.text('10 / 10'), findsNothing);
    expect(find.text('第10章：测试标题10'), findsNothing);
    expect(find.text('100.0%'), findsNothing);
  });

  testWidgets('目录、夜间和设置位于底部菜单', (tester) async {
    var chaptersOpened = false;
    var nightModeToggled = false;
    var settingsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderChrome(
            visible: true,
            title: '测试章节',
            backgroundColor: const Color(0xFFE0C4A1),
            foregroundColor: const Color(0xFF2A2318),
            currentChapter: 2,
            totalChapters: 10,
            onOpenChapters: () => chaptersOpened = true,
            nightMode: true,
            onToggleNightMode: () => nightModeToggled = true,
            onOpenSettings: () => settingsOpened = true,
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('夜间'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('夜间模式'), findsOneWidget);
    final sliderCenter = tester.getCenter(find.byType(Slider));
    final directoryIconCenter = tester.getCenter(
      find.byIcon(Icons.list_alt_rounded),
    );
    expect(directoryIconCenter.dy - sliderCenter.dy, lessThan(60));

    await tester.tap(find.text('目录'));
    await tester.tap(find.text('夜间'));
    await tester.tap(find.text('设置'));

    expect(chaptersOpened, isTrue);
    expect(nightModeToggled, isTrue);
    expect(settingsOpened, isTrue);
  });
}
