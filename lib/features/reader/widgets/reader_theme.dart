import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../data/api/models/book.dart';
import '../../../data/providers.dart';
import '../../../data/settings/app_settings.dart';

/// 阅读页的亮暗独立于全局主题：算出来的亮暗与应用不一致时就在这里重建一套
/// ThemeData，正文、工具栏和从阅读页弹出的面板都跟着它走。
class ReaderThemeScope extends ConsumerWidget {
  const ReaderThemeScope({super.key, required this.type, required this.child});

  final BookType type;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(
      appSettingsProvider.select(
        (settings) => readerBrightness(
          type == BookType.comic ? settings.comicReader : settings.novelReader,
        ),
      ),
    );
    final palette = ref.watch(appSettingsProvider.select(AppPalette.of));
    final ambient = Theme.of(context);
    // 这一层 Theme 常在：亮暗一致时也要套，否则切换会改变子树深度，阅读器的
    // State 连同章节窗口一起被丢掉，退回初始章节。
    return Theme(
      data: brightness == null || ambient.brightness == brightness
          ? ambient
          : buildAppThemeFor(
              brightness: brightness,
              palette: palette,
              dynamicScheme: AppDynamicSchemes.maybeOf(context)
                  ?.forBrightness(brightness),
            ),
      child: child,
    );
  }
}

/// 阅读页要用的亮暗，null 表示跟随应用。
///
/// 自定义背景色的底色与前景色都由这个颜色算出来，主题跟着底色的明暗走才不会出现
/// 浅色主题配黑底这种组合，所以这一档不看 `readerTheme`。
Brightness? readerBrightness(ReaderPreferences settings) =>
    readerThemeLocked(settings)
    ? ThemeData.estimateBrightnessForColor(
        parseSeedColor(settings.backgroundColorValue),
      )
    : switch (settings.theme) {
        ReaderThemeSetting.followApp => null,
        ReaderThemeSetting.light => Brightness.light,
        ReaderThemeSetting.dark => Brightness.dark,
      };

/// 亮暗由背景色定死，不给切。
bool readerThemeLocked(ReaderPreferences settings) =>
    settings.backgroundMode == ReaderBackgroundMode.custom;

/// 夜间开关只改阅读页的亮暗，不碰全局 `theme`。目标亮暗与全局一致时写回 followApp，
/// 免得把「跟随系统」换成固定值后再也回不去。
void toggleReaderNightMode(BuildContext context, WidgetRef ref, BookType type) {
  final appBrightness = resolveBrightness(
    ref.read(appSettingsProvider).theme,
    MediaQuery.platformBrightnessOf(context),
  );
  final target = Theme.of(context).brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  final ReaderThemeSetting readerTheme;
  if (target == appBrightness) {
    readerTheme = ReaderThemeSetting.followApp;
  } else {
    readerTheme = target == Brightness.dark
        ? ReaderThemeSetting.dark
        : ReaderThemeSetting.light;
  }
  ref
      .read(settingsControllerProvider)
      .update(
        (settings) => type == BookType.comic
            ? settings.copyWith(
                comicReader: settings.comicReader.copyWith(theme: readerTheme),
              )
            : settings.copyWith(
                novelReader: settings.novelReader.copyWith(theme: readerTheme),
              ),
      );
}
