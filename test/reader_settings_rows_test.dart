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
  testWidgets('小说滚动模式下只禁用小说双页设置', (tester) async {
    final controller = await _pumpSettings(
      tester,
      const AppSettings(
        novelReader: ReaderPreferences(viewMode: ReaderViewMode.scroll),
        comicReader: ReaderPreferences(dualPageEnabled: true),
      ),
    );

    expect(_switchFor(tester, '双页模式').onChanged, isNull);
    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(controller.settings.novelReader.dualPageEnabled, isFalse);
    expect(controller.settings.comicReader.dualPageEnabled, isTrue);
  });

  testWidgets('小说设置只显示小说选项', (tester) async {
    await _pumpSettings(tester, const AppSettings());

    expect(find.text('字号'), findsOneWidget);
    expect(find.text('章节标题'), findsOneWidget);
    expect(find.text('预渲染前后章节'), findsOneWidget);
    expect(find.text('漫画分页方向'), findsNothing);
  });

  testWidgets('漫画设置只显示漫画选项并独立更新', (tester) async {
    final controller = await _pumpSettings(
      tester,
      const AppSettings(),
      type: BookType.comic,
    );

    expect(find.text('漫画分页方向'), findsOneWidget);
    expect(find.text('字号'), findsNothing);
    expect(find.text('章节标题'), findsNothing);
    expect(find.text('预渲染前后章节'), findsNothing);

    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(controller.settings.comicReader.dualPageEnabled, isTrue);
    expect(controller.settings.novelReader.dualPageEnabled, isFalse);
  });
  testWidgets('软件设置把阅读单列并提供小说漫画入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('小说'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
  });
}
