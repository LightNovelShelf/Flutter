import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_style.dart';
import 'package:lightnovel/shared/widgets/reader_html_block.dart';

const _style = ReaderContentStyle(
  fontSize: 16,
  lineHeight: 1.5,
  lineSpace: 8,
  firstLineIndent: false,
  justify: false,
);

Future<double> _renderHeight(
  WidgetTester tester,
  String markup, {
  required bool applyLineSpace,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: const ValueKey('subject'),
            width: 300,
            child: ReaderHtmlBlock(
              markup: markup,
              style: _style,
              applyLineSpace: applyLineSpace,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byKey(const ValueKey('subject'))).height;
}

void main() {
  testWidgets('段间距同时作用于段落和标题文本块', (tester) async {
    for (final markup in const <String>['<p>正文</p>', '<h1>标题</h1>']) {
      final withoutSpacing = await _renderHeight(
        tester,
        markup,
        applyLineSpace: false,
      );
      final withSpacing = await _renderHeight(
        tester,
        markup,
        applyLineSpace: true,
      );

      expect(
        withSpacing - withoutSpacing,
        closeTo(_style.lineSpace, 0.01),
        reason: markup,
      );
    }
  });
}
