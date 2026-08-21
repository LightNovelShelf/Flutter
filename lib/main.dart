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
import 'data/session/auth_controller.dart';
import 'data/settings/app_settings.dart';

/// 开发期通过 `--dart-define=REFRESH_TOKEN=...` 注入的刷新令牌，用于跳过手动登录。
const String _injectedRefreshToken =
    String.fromEnvironment('REFRESH_TOKEN');

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
      overrides: <Override>[appRuntimeProvider.overrideWithValue(runtime)],
      child: const LightNovelShelfApp(),
    ),
  );
}

class LightNovelShelfApp extends ConsumerWidget {
  const LightNovelShelfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(routerProvider);
    // 亮暗由 `themeMode` 决定，两套主题都要构建。

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp.router(
          title: '轻书架',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: buildAppTheme(
            brightness: Brightness.light,
            settings: settings,
            dynamicScheme: lightDynamic,
          ),
          darkTheme: buildAppTheme(
            brightness: Brightness.dark,
            settings: settings,
            dynamicScheme: darkDynamic,
          ),
          themeMode: switch (settings.theme) {
            ThemeSetting.light => ThemeMode.light,
            ThemeSetting.dark => ThemeMode.dark,
            ThemeSetting.system => ThemeMode.system,
          },
          locale: switch (settings.language) {
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
        );
      },
    );
  }
}
