import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';

/// OLED 纯黑模式下的覆盖色。
class OledPalette {
  const OledPalette._();

  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF000000);
  static const Color card = Color(0xFF0E1014);
  static const Color surfaceContainerHighest = Color(0xFF1A1A1A);
  static const Color label = Color(0xFFEFEFEF);
  static const Color secondaryLabel = Color(0xFFC7C7C7);
  static const Color separator = Color(0xFF252525);
}

Color parseSeedColor(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

/// [parseSeedColor] 的逆运算，产出 `#RRGGBB`。
String formatHexColor(Color color) {
  final rgb =
      ((color.r * 255).round() << 16) |
      ((color.g * 255).round() << 8) |
      (color.b * 255).round();
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Brightness resolveBrightness(ThemeSetting theme, Brightness platform) =>
    switch (theme) {
      ThemeSetting.light => Brightness.light,
      ThemeSetting.dark => Brightness.dark,
      ThemeSetting.system => platform,
    };

/// 按感知亮度在黑白之间挑前景色，阈值 186。
Color onAccentColor(Color accent) {
  final luminance =
      0.299 * (accent.r * 255) +
      0.587 * (accent.g * 255) +
      0.114 * (accent.b * 255);
  return luminance > 186 ? Colors.black : Colors.white;
}

/// 决定 `ThemeData` 的设置子集。根节点只订阅它，拖阅读器字号之类的写入就不会重建
/// `MaterialApp.router`。
@immutable
class AppPalette {
  const AppPalette({
    required this.useSystemColor,
    required this.seedColorValue,
    required this.oledBlack,
  });

  static AppPalette of(AppSettings settings) => AppPalette(
    useSystemColor: settings.useSystemColor,
    seedColorValue: settings.seedColorValue,
    oledBlack: settings.oledBlack,
  );

  final bool useSystemColor;
  final String seedColorValue;
  final bool oledBlack;

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.useSystemColor == useSystemColor &&
      other.seedColorValue == seedColorValue &&
      other.oledBlack == oledBlack;

  @override
  int get hashCode => Object.hash(useSystemColor, seedColorValue, oledBlack);
}

/// 按输入缓存主题实例。新建 `ThemeData` 会让 `AnimatedTheme` 判定主题变更，标脏所有
/// `Theme.of` 依赖者（含 indexedStack 里的离屏 tab），实测一次导航多 30~43ms。
typedef _ThemeKey = (Brightness, AppPalette, ColorScheme?);

final Map<_ThemeKey, ThemeData> _themeCache = <_ThemeKey, ThemeData>{};

ThemeData buildAppTheme({
  required Brightness brightness,
  required AppSettings settings,
  ColorScheme? dynamicScheme,
}) => buildAppThemeFor(
  brightness: brightness,
  palette: AppPalette.of(settings),
  dynamicScheme: dynamicScheme,
);

ThemeData buildAppThemeFor({
  required Brightness brightness,
  required AppPalette palette,
  ColorScheme? dynamicScheme,
}) {
  final _ThemeKey key = (brightness, palette, dynamicScheme);
  final ThemeData? cached = _themeCache[key];
  if (cached != null) return cached;
  // 配色改动会不断产生新键，超过上限就整体清空。
  if (_themeCache.length >= 8) _themeCache.clear();
  return _themeCache[key] = _buildAppTheme(
    brightness: brightness,
    palette: palette,
    dynamicScheme: dynamicScheme,
  );
}

ThemeData _buildAppTheme({
  required Brightness brightness,
  required AppPalette palette,
  ColorScheme? dynamicScheme,
}) {
  final useDynamic = palette.useSystemColor && dynamicScheme != null;
  var scheme = useDynamic
      ? dynamicScheme.copyWith(brightness: brightness)
      : ColorScheme.fromSeed(
          seedColor: parseSeedColor(palette.seedColorValue),
          brightness: brightness,
        );

  final isOledDark = brightness == Brightness.dark && palette.oledBlack;
  if (isOledDark) {
    scheme = scheme.copyWith(
      surface: OledPalette.surface,
      surfaceContainer: OledPalette.card,
      surfaceContainerLow: OledPalette.card,
      surfaceContainerHighest: OledPalette.surfaceContainerHighest,
      onSurface: OledPalette.label,
      onSurfaceVariant: OledPalette.secondaryLabel,
      outlineVariant: OledPalette.separator,
    );
  }

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: isOledDark
        ? OledPalette.background
        : scheme.surface,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: isOledDark ? OledPalette.background : scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: isOledDark ? 0 : 3,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isOledDark ? OledPalette.background : scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 3,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: base.textTheme.bodyLarge?.copyWith(
        color: scheme.onSurface,
      ),
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isOledDark
          ? OledPalette.card
          : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    // 默认的 FadeForwards 转场 450ms 全程合成两个全屏 opacity 层且不做快照，切页时
    // 与新页首次 build/layout/解码撞在一起。Zoom 系转场一次栅格捕获后只做纹理变换。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android:
            PredictiveBackFullscreenPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
