import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/api/models/book.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/settings/reader_settings_screen.dart';
import 'package:lightnovel/features/settings/settings_screen.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

Future<SettingsController> _pumpSettings(
  WidgetTester tester,
  AppSettings settings, {
  BookType type = BookType.novel,
}) async {
  final controller = SettingsController(_MemoryStore(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsControllerProvider.overrideWith((_) => controller),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ReaderSettingsContent(type: type)),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

ListTile _tileFor(WidgetTester tester, String title) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(ListTile),
  );
  expect(row, findsOneWidget);
  return tester.widget<ListTile>(row);
}

Switch _switchFor(WidgetTester tester, String title) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(ListTile),
  );
  expect(row, findsOneWidget);
  return tester.widget<Switch>(
    find.descendant(of: row, matching: find.byType(Switch)),
  );
}

void main() {
  testWidgets('小说上下模式下禁用分页设置，翻页动画仍可切回分页', (tester) async {
    final controller = await _pumpSettings(
      tester,
      const AppSettings(
        novelReader: ReaderPreferences(
          pageTurnAnimation: ReaderPageTurnAnimation.vertical,
        ),
        comicReader: ReaderPreferences(dualPageEnabled: false),
      ),
    );

    expect(find.text('阅读模式'), findsNothing);
    expect(_switchFor(tester, '页码胶囊').onChanged, isNull);
    expect(_switchFor(tester, '双页模式').onChanged, isNull);
    expect(_tileFor(tester, '翻页动画').enabled, isTrue);
    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(controller.settings.novelReader.dualPageEnabled, isTrue);
    expect(controller.settings.comicReader.dualPageEnabled, isFalse);
    expect(controller.settings.novelReader.statusPillsEnabled, isTrue);

    await tester.ensureVisible(find.text('翻页动画'));
    await tester.tap(find.text('翻页动画'));
    await tester.pumpAndSettle();
    for (final label in <String>['仿真', '覆盖', '平移', '无动画']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('仿真'));
    await tester.pumpAndSettle();
    expect(
      controller.settings.novelReader.pageTurnAnimation,
      ReaderPageTurnAnimation.simulation,
    );
    expect(_switchFor(tester, '页码胶囊').onChanged, isNotNull);
  });

  testWidgets('小说设置只显示小说选项', (tester) async {
    await _pumpSettings(tester, const AppSettings());

    expect(find.text('字号'), findsOneWidget);
    expect(find.text('章节标题'), findsOneWidget);
    expect(find.text('预渲染前后章节'), findsOneWidget);
    expect(find.text('翻页动画'), findsOneWidget);
    expect(find.text('漫画分页方向'), findsNothing);
  });

  testWidgets('漫画设置只显示漫画选项并独立更新', (tester) async {
    final controller = await _pumpSettings(
      tester,
      const AppSettings(
        novelReader: ReaderPreferences(dualPageEnabled: false),
        comicReader: ReaderPreferences(dualPageEnabled: false),
      ),
      type: BookType.comic,
    );

    expect(find.text('漫画分页方向'), findsOneWidget);
    expect(find.text('字号'), findsNothing);
    expect(find.text('章节标题'), findsNothing);
    expect(find.text('预渲染前后章节'), findsNothing);
    expect(_switchFor(tester, '错位双页').onChanged, isNull);
    expect(find.text('翻页动画'), findsOneWidget);

    await tester.ensureVisible(find.text('翻页动画'));
    await tester.tap(find.text('翻页动画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('平移'));
    await tester.pumpAndSettle();
    expect(
      controller.settings.comicReader.pageTurnAnimation,
      ReaderPageTurnAnimation.slide,
    );
    expect(
      controller.settings.novelReader.pageTurnAnimation,
      ReaderPageTurnAnimation.simulation,
    );

    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(controller.settings.comicReader.dualPageEnabled, isTrue);
    expect(controller.settings.novelReader.dualPageEnabled, isFalse);
    expect(_switchFor(tester, '错位双页').onChanged, isNotNull);
    expect(find.text('错位双页'), findsOneWidget);
    await tester.ensureVisible(find.text('错位双页'));
    await tester.tap(find.text('错位双页'));
    await tester.pump();
    expect(controller.settings.comicReader.dualPageOffsetEnabled, isTrue);

    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(find.text('错位双页'), findsOneWidget);
    expect(_switchFor(tester, '错位双页').onChanged, isNull);
  });

  testWidgets('漫画上下模式下保留并禁用分页设置', (tester) async {
    await _pumpSettings(
      tester,
      const AppSettings(
        comicReader: ReaderPreferences(
          pageTurnAnimation: ReaderPageTurnAnimation.vertical,
        ),
      ),
      type: BookType.comic,
    );

    expect(_switchFor(tester, '页码胶囊').onChanged, isNull);
    expect(_tileFor(tester, '翻页动画').enabled, isTrue);
    expect(_switchFor(tester, '错位双页').onChanged, isNull);
  });

  testWidgets('背景颜色在非自定义模式下保留并禁用', (tester) async {
    await _pumpSettings(tester, const AppSettings());

    expect(find.text('背景颜色'), findsOneWidget);
    expect(_tileFor(tester, '背景颜色').enabled, isFalse);
  });

  testWidgets('iOS 隐藏不支持的平台设置', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpSettings(tester, const AppSettings());

      expect(find.text('沉浸式阅读'), findsNothing);
      expect(find.text('使用音量键翻页'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('软件设置把阅读单列并提供小说漫画入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('小说'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
  });
}
