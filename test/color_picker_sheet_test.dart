import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/color_picker_sheet.dart';

Future<void> _openPicker(
  WidgetTester tester,
  ValueChanged<String?> onPicked,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => onPicked(
                await showColorPickerSheet(
                  context,
                  initial: '#FFFFFF',
                  title: '背景颜色',
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

String _fieldValue(WidgetTester tester, String key) => tester
    .widget<TextField>(find.byKey(ValueKey<String>(key)))
    .controller!
    .text;

Future<void> _confirm(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final button = find.widgetWithText(FilledButton, '使用此颜色');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('十六进制输入同步 RGB 并返回标准颜色值', (tester) async {
    String? picked;
    await _openPicker(tester, (value) => picked = value);

    await tester.enterText(
      find.byKey(const ValueKey<String>('color-picker-hex')),
      '#1a2b3c',
    );
    await tester.pump();

    expect(_fieldValue(tester, 'color-picker-red'), '26');
    expect(_fieldValue(tester, 'color-picker-green'), '43');
    expect(_fieldValue(tester, 'color-picker-blue'), '60');

    await _confirm(tester);
    expect(picked, '#1A2B3C');
  });

  testWidgets('RGB 输入校验范围并同步十六进制值', (tester) async {
    String? picked;
    await _openPicker(tester, (value) => picked = value);

    final red = find.byKey(const ValueKey<String>('color-picker-red'));
    await tester.enterText(red, '256');
    await tester.pump();

    expect(find.text('0–255'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '使用此颜色'))
          .onPressed,
      isNull,
    );

    await tester.enterText(red, '12');
    await tester.enterText(
      find.byKey(const ValueKey<String>('color-picker-green')),
      '34',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('color-picker-blue')),
      '56',
    );
    await tester.pump();

    expect(_fieldValue(tester, 'color-picker-hex'), '#0C2238');
    expect(find.text('0–255'), findsNothing);

    await _confirm(tester);
    expect(picked, '#0C2238');
  });
}
