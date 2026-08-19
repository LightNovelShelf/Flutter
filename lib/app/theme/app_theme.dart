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

Brightness resolveBrightness(ThemeSetting theme, Brightness platform) =>
    switch (theme) {
      ThemeSetting.light => Brightness.light,
      ThemeSetting.dark => Brightness.dark,
      ThemeSetting.system => platform,
    };

/// 按感知亮度在黑白之间挑前景色，阈值 186。
Color onAccentColor(Color accent) {
  final luminance = 0.299 * (accent.r * 255) +
      0.587 * (accent.g * 255) +
      0.114 * (accent.b * 255);
  return luminance > 186 ? Colors.black : Colors.white;
}

ThemeData buildAppTheme({
  required Brightness brightness,
  required AppSettings settings,
  ColorScheme? dynamicScheme,
}) {
  final useDynamic = settings.useSystemColor && dynamicScheme != null;
  var scheme = useDynamic
      ? dynamicScheme.copyWith(brightness: brightness)
      : ColorScheme.fromSeed(
          seedColor: parseSeedColor(settings.seedColorValue),
          brightness: brightness,
        );

  final isOledDark = brightness == Brightness.dark && settings.oledBlack;
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
    scaffoldBackgroundColor: isOledDark ? OledPalette.background : scheme.surface,
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
      titleTextStyle: base.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      subtitleTextStyle:
          base.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      iconColor: scheme.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isOledDark ? OledPalette.card : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
  );
}
