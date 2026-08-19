import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/app/theme/app_theme.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/auth/widgets/auth_form_scaffold.dart';

/// 输入框布局回归。
///
/// 要量的是 `InputDecorator` 用来画填充与边框的那个容器盒子，而不是 `TextField`
/// 的外层盒子：外层被 `SizedBox(height: 52)` 之类撑住时，`getSize(TextField)`
/// 照样返回 52，而容器只有一行文字高 —— 这就是「输入框坍缩」的形态。
///
/// 容器是 `_RenderDecoration` 的一个 child slot，落在字段内唯一的 `CustomPaint`
/// 上，它的尺寸就是绘制尺寸。
void main() {
  final ThemeData theme = buildAppTheme(
    brightness: Brightness.light,
    settings: const AppSettings(),
  );

  Future<void> pumpFields(WidgetTester tester, {double textScale = 1.0}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AuthTextField(
                      controller: TextEditingController(),
                      hintText: '邮箱',
                    ),
                    const SizedBox(height: 13),
                    AuthPasswordField(
                      controller: TextEditingController(),
                      hintText: '密码',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 字段实际绘制出来的装饰容器尺寸。
  Size decorationSize(WidgetTester tester, Finder field) {
    final Finder container =
        find.descendant(of: field, matching: find.byType(CustomPaint));
    // Flutter 改了 InputDecorator 的实现时要显式失败，而不是悄悄量错东西。
    expect(
      container,
      findsOneWidget,
      reason: '预期字段内只有装饰容器这一个 CustomPaint',
    );
    return tester.getSize(container);
  }

  // 容器高度是确定值：13 的上下内边距 + 26 的输入行高 = 52，真机与测试环境一致。
  const double expectedHeight = 52;

  testWidgets('两个输入框画出来的高度都是 52', (WidgetTester tester) async {
    await pumpFields(tester);

    final double email =
        decorationSize(tester, find.byType(AuthTextField)).height;
    final double password =
        decorationSize(tester, find.byType(AuthPasswordField)).height;

    expect(email, password);
    expect(email, expectedHeight);
  });

  testWidgets('放大字号时输入框跟着长高，而不是固定高度裁掉文字', (WidgetTester tester) async {
    await pumpFields(tester);
    final double normal =
        decorationSize(tester, find.byType(AuthTextField)).height;

    await pumpFields(tester, textScale: 1.5);
    final double emailScaled =
        decorationSize(tester, find.byType(AuthTextField)).height;
    final double passwordScaled =
        decorationSize(tester, find.byType(AuthPasswordField)).height;

    expect(emailScaled, greaterThan(normal));
    expect(emailScaled, passwordScaled, reason: '放大后两个框仍要等高');
  });

  testWidgets('输入框之间的间距是 13', (WidgetTester tester) async {
    await pumpFields(tester);

    final Rect email = tester.getRect(find.byType(AuthTextField));
    final Rect password = tester.getRect(find.byType(AuthPasswordField));

    expect(password.top - email.bottom, closeTo(13, 0.01));
    // 外层盒子不该再自带固定高度：它应当由装饰容器撑出来。
    expect(email.height, decorationSize(tester, find.byType(AuthTextField)).height);
  });
}
