import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/comments/reply_compose_sheet.dart';

/// 发表面板跟随键盘时的重建范围与取焦时机。

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showReplyComposeSheet(
                context,
                hintText: '写评论',
                onSubmit: (_) async {},
                describeError: (_) => '失败',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

bool _focused(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

void main() {
  testWidgets('键盘 inset 变化只挪内边距，不重建输入框子树', (tester) async {
    await _open(tester);
    await tester.pumpAndSettle();

    double insetOf() => tester
        .widget<Padding>(
          find
              .ancestor(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Padding),
              )
              .first,
        )
        .padding
        .resolve(TextDirection.ltr)
        .bottom;

    expect(insetOf(), 0);
    final TextField before = tester.widget<TextField>(find.byType(TextField));

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(insetOf(), 600 / tester.view.devicePixelRatio);
    expect(
      identical(tester.widget<TextField>(find.byType(TextField)), before),
      isTrue,
      reason: '子树被重建了，键盘动画每帧都要重建 TextField',
    );
  });

  testWidgets('入场动画跑完才取焦，避免 IME 动画被取消重来', (tester) async {
    await _open(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_focused(tester), isFalse, reason: '面板还在入场就弹了键盘');

    await tester.pumpAndSettle();
    expect(_focused(tester), isTrue);
  });
}
