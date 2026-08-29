import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/settings/content_settings_screen.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

void main() {
  testWidgets('内容设置里有「图片保存到专属目录」，默认关，拨动后写进设置', (tester) async {
    final controller = SettingsController(_MemoryStore(), const AppSettings());
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsControllerProvider.overrideWith((_) => controller),
        ],
        child: const MaterialApp(home: ContentSettingsScreen()),
      ),
    );
    await tester.pump();

    expect(controller.settings.imageSaveToOwnFolder, isFalse);
    final row = find.ancestor(
      of: find.text('图片保存到专属目录'),
      matching: find.byType(ListTile),
    );
    expect(row, findsOneWidget);
    await tester.scrollUntilVisible(row, 200);
    final Finder toggle = find.descendant(
      of: row,
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pump();
    expect(controller.settings.imageSaveToOwnFolder, isTrue);
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });
}
