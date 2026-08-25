import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/settings/reader_settings_screen.dart';

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
  AppSettings settings,
) async {
  final controller = SettingsController(_MemoryStore(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsControllerProvider.overrideWith((_) => controller),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ReaderSettingsContent()),
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
  testWidgets('滚动模式下双页开关置灰，点不动', (tester) async {
    final controller = await _pumpSettings(
      tester,
      const AppSettings(readerViewMode: ReaderViewMode.scroll),
    );

    expect(_switchFor(tester, '双页模式').onChanged, isNull);

    // 整行也不响应点按，值不会被翻过去。
    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(controller.settings.readerDualPageEnabled, isFalse);
  });

  testWidgets('翻页模式下双页开关可用', (tester) async {
    final controller = await _pumpSettings(
      tester,
      const AppSettings(readerViewMode: ReaderViewMode.paged),
    );

    expect(_switchFor(tester, '双页模式').onChanged, isNotNull);

    await tester.ensureVisible(find.text('双页模式'));
    await tester.tap(find.text('双页模式'));
    await tester.pump();
    expect(controller.settings.readerDualPageEnabled, isTrue);
  });

  testWidgets('页码胶囊不跟着阅读模式置灰：滚动模式下漫画仍用它', (tester) async {
    await _pumpSettings(
      tester,
      const AppSettings(readerViewMode: ReaderViewMode.scroll),
    );

    expect(_switchFor(tester, '页码胶囊').onChanged, isNotNull);
  });
}
