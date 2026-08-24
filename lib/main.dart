import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme/app_theme.dart';
import 'data/app_runtime.dart';
import 'data/providers.dart';
import 'data/retry_policy.dart';
import 'data/session/auth_controller.dart';
import 'data/settings/app_settings.dart';

/// 开发期通过 `--dart-define=REFRESH_TOKEN=...` 注入的刷新令牌，用于跳过手动登录。
const String _injectedRefreshToken = String.fromEnvironment('REFRESH_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final runtime = await AppRuntime.bootstrap();
  if (_injectedRefreshToken.isNotEmpty) {
    await runtime.credentials.write(
      AuthCredentialKeys.refreshToken,
      _injectedRefreshToken,
    );
  }
  // 会话恢复与实时连接放到后台，不阻塞首帧。
  unawaited(runtime.start());

  runApp(
    ProviderScope(
      retry: apiRetry,
      overrides: <Override>[appRuntimeProvider.overrideWithValue(runtime)],
      child: const LightNovelShelfApp(),
    ),
  );
}

class LightNovelShelfApp extends ConsumerWidget {
  const LightNovelShelfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 根节点只订阅主题与语言相关字段，字号、阅读器排版之类的写入不再重建
    // MaterialApp.router → Router → Navigator。
    final palette = ref.watch(appSettingsProvider.select(AppPalette.of));
    final theme = ref.watch(
      appSettingsProvider.select((settings) => settings.theme),
    );
    final language = ref.watch(
      appSettingsProvider.select((settings) => settings.language),
    );
    final router = ref.watch(routerProvider);
    // 亮暗由 `themeMode` 决定，两套主题都要构建。

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return AppDynamicSchemes(
          light: lightDynamic,
          dark: darkDynamic,
          child: MaterialApp.router(
            title: '轻书架',
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: buildAppThemeFor(
              brightness: Brightness.light,
              palette: palette,
              dynamicScheme: lightDynamic,
            ),
            darkTheme: buildAppThemeFor(
              brightness: Brightness.dark,
              palette: palette,
              dynamicScheme: darkDynamic,
            ),
            themeMode: switch (theme) {
              ThemeSetting.light => ThemeMode.light,
              ThemeSetting.dark => ThemeMode.dark,
              ThemeSetting.system => ThemeMode.system,
            },
            locale: switch (language) {
              LanguageSetting.zhCN => const Locale('zh', 'CN'),
              LanguageSetting.zhTW => const Locale('zh', 'TW'),
              LanguageSetting.system => null,
            },
            supportedLocales: const <Locale>[
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
            ],
            localizationsDelegates: const <LocalizationsDelegate<Object?>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        );
      },
    );
  }
}
