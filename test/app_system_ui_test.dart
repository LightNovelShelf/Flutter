import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/app_system_ui.dart';

void main() {
  test('默认系统栏样式禁用透明栏对比度遮罩', () {
    for (final brightness in Brightness.values) {
      final style = AppSystemUi.defaultOverlayStyle(brightness);
      final iconBrightness = brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;

      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, iconBrightness);
      expect(style.statusBarBrightness, brightness);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarDividerColor, Colors.transparent);
      expect(style.systemNavigationBarIconBrightness, iconBrightness);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    }
  });
}
