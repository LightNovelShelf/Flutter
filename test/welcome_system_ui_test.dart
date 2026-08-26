import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/auth/welcome_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('欢迎页在 $brightness 下禁用系统栏遮罩', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            welcomeCoversProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const WelcomeScreen(),
          ),
        ),
      );

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(WelcomeScreen),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );

      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.systemStatusBarContrastEnforced, isFalse);
      expect(region.value.systemNavigationBarColor, Colors.transparent);
      expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    });
  }
}
