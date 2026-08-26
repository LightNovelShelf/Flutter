import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/widgets/reader_shell.dart';

/// 观察某一层的 State 有没有被丢掉。
class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _ChromeProbe extends StatefulWidget {
  const _ChromeProbe();

  @override
  State<_ChromeProbe> createState() => _ChromeProbeState();
}

class _ChromeProbeState extends State<_ChromeProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget shell({bool paperTexture = false, bool overlay = false}) => MaterialApp(
  home: ReaderShell(
    background: const Color(0xFFE0C4A1),
    paperTexture: paperTexture,
    body: const _Probe(),
    overlay: overlay
        ? const Positioned(left: 0, bottom: 0, child: Text('页码'))
        : null,
    chrome: const _ChromeProbe(),
  ),
);

void main() {
  testWidgets('切纸质背景不重建正文层', (tester) async {
    await tester.pumpWidget(shell());
    final before = tester.state<_ProbeState>(find.byType(_Probe));

    await tester.pumpWidget(shell(paperTexture: true));

    expect(tester.state<_ProbeState>(find.byType(_Probe)), same(before));
  });

  testWidgets('叠层出现或消失不重建工具栏', (tester) async {
    await tester.pumpWidget(shell());
    final before = tester.state<_ChromeProbeState>(find.byType(_ChromeProbe));

    await tester.pumpWidget(shell(overlay: true));

    expect(
      tester.state<_ChromeProbeState>(find.byType(_ChromeProbe)),
      same(before),
    );
  });

  testWidgets('阅读器禁用透明系统栏对比度遮罩', (tester) async {
    await tester.pumpWidget(shell());

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(ReaderShell),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );

    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.systemStatusBarContrastEnforced, isFalse);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarContrastEnforced, isFalse);
  });
}
