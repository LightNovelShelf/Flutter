import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/reader/widgets/reader_theme.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// 阅读页里的一个按钮，点它切夜间；同时把当前 brightness 显示出来。
class _Probe extends ConsumerWidget {
  const _Probe();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: () => toggleReaderNightMode(context, ref),
    child: Text(Theme.of(context).brightness.name),
  );
}

/// 观察子树 State 有没有被丢掉。
class _StateProbe extends StatefulWidget {
  const _StateProbe();

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<SettingsController> pumpReader(
  WidgetTester tester, {
  required AppSettings settings,
  Brightness platform = Brightness.light,
}) async {
  final controller = SettingsController(_MemoryStore(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: switch (settings.theme) {
          ThemeSetting.light => ThemeMode.light,
          ThemeSetting.dark => ThemeMode.dark,
          ThemeSetting.system => ThemeMode.system,
        },
        home: MediaQuery(
          data: MediaQueryData(platformBrightness: platform),
          child: const ReaderThemeScope(
            child: Scaffold(
              body: Column(children: <Widget>[_Probe(), _StateProbe()]),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('readerTheme 只改阅读页亮暗，全局 theme 不动', (tester) async {
    final controller = await pumpReader(
      tester,
      settings: const AppSettings(readerTheme: ReaderThemeSetting.dark),
    );

    expect(find.text('dark'), findsOneWidget);
    expect(controller.settings.theme, ThemeSetting.system);
  });

  testWidgets('夜间开关写 readerTheme，不覆盖跟随系统的全局主题', (tester) async {
    final controller = await pumpReader(tester, settings: const AppSettings());

    expect(find.text('light'), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(controller.settings.theme, ThemeSetting.system);
    expect(controller.settings.readerTheme, ReaderThemeSetting.dark);
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('切回与全局一致的亮暗时写 followApp', (tester) async {
    final controller = await pumpReader(
      tester,
      settings: const AppSettings(readerTheme: ReaderThemeSetting.dark),
    );

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(controller.settings.readerTheme, ReaderThemeSetting.followApp);
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('followApp 时跟着全局主题走', (tester) async {
    await pumpReader(
      tester,
      settings: const AppSettings(theme: ThemeSetting.dark),
    );

    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('自定义背景色：亮暗按底色定，readerTheme 不起作用', (tester) async {
    await pumpReader(
      tester,
      settings: const AppSettings(
        readerBackgroundMode: ReaderBackgroundMode.custom,
        readerBackgroundColorValue: '#000000',
        readerTheme: ReaderThemeSetting.light,
      ),
    );

    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('自定义浅底色：即使 readerTheme 是深色也走浅色', (tester) async {
    await pumpReader(
      tester,
      settings: const AppSettings(
        readerBackgroundMode: ReaderBackgroundMode.custom,
        readerBackgroundColorValue: '#F7F1E3',
        readerTheme: ReaderThemeSetting.dark,
      ),
    );

    expect(find.text('light'), findsOneWidget);
  });

  test('自定义背景色下锁住主题，其余模式不锁', () {
    expect(
      readerThemeLocked(
        const AppSettings(readerBackgroundMode: ReaderBackgroundMode.custom),
      ),
      isTrue,
    );
    for (final mode in <ReaderBackgroundMode>[
      ReaderBackgroundMode.auto,
      ReaderBackgroundMode.paper,
    ]) {
      expect(
        readerThemeLocked(AppSettings(readerBackgroundMode: mode)),
        isFalse,
      );
    }
  });
  testWidgets('切阅读页亮暗不重建子树，阅读器 State 保持', (tester) async {
    await pumpReader(tester, settings: const AppSettings());
    final before = tester.state<_StateProbeState>(find.byType(_StateProbe));

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(find.text('dark'), findsOneWidget);
    expect(
      tester.state<_StateProbeState>(find.byType(_StateProbe)),
      same(before),
    );
  });
  test('readerTheme 走编解码往返', () {
    final encoded = const AppSettings(readerTheme: ReaderThemeSetting.dark)
        .encode();
    expect(AppSettings.decode(encoded).readerTheme, ReaderThemeSetting.dark);
  });
}
