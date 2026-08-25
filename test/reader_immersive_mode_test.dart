import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/reader_immersive_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> modes = <String>[];

  setUp(() {
    modes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> sendLifecycle(WidgetTester tester, String state) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage('AppLifecycleState.$state'),
          (_) {},
        );
    await tester.pumpAndSettle();
  }

  Widget wrap({required bool enabled, Widget? child}) => MaterialApp(
    home: ReaderImmersiveMode(
      enabled: enabled,
      child: child ?? const Scaffold(body: SizedBox.expand()),
    ),
  );

  /// 平台覆盖必须在用例体内还原，测试框架会在体末尾查它有没有留下。
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// 控制器是单例：用例结束必须拆掉 widget 树，否则没 dispose 的实例会继续算数。
  void disposeAfter(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('开启时藏起系统栏，离开阅读器再还回来', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      disposeAfter(tester);

      await tester.pumpWidget(wrap(enabled: true));
      await tester.pumpAndSettle();
      expect(modes, <String>['SystemUiMode.immersiveSticky']);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(modes, <String>[
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
      ]);
    });
  });

  testWidgets('设置关闭时不动系统栏', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      disposeAfter(tester);

      await tester.pumpWidget(wrap(enabled: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(modes, isEmpty);
    });
  });

  testWidgets('阅读中改设置即时生效', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      disposeAfter(tester);

      await tester.pumpWidget(wrap(enabled: false));
      await tester.pumpAndSettle();
      expect(modes, isEmpty);

      await tester.pumpWidget(wrap(enabled: true));
      await tester.pumpAndSettle();
      expect(modes, <String>['SystemUiMode.immersiveSticky']);

      await tester.pumpWidget(wrap(enabled: false));
      await tester.pumpAndSettle();
      expect(modes, <String>[
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
      ]);
    });
  });

  testWidgets('弹层盖住阅读器时系统栏保持隐藏', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      disposeAfter(tester);

      await tester.pumpWidget(wrap(enabled: true));
      await tester.pumpAndSettle();
      expect(modes, <String>['SystemUiMode.immersiveSticky']);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        showModalBottomSheet<void>(
          context: navigator.context,
          builder: (_) => const SizedBox(height: 120),
        ),
      );
      await tester.pumpAndSettle();
      // 设置面板一开就把系统栏放回来，关掉再藏起来，屏幕会跳两次。
      expect(modes, <String>['SystemUiMode.immersiveSticky']);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(modes, <String>['SystemUiMode.immersiveSticky']);
    });
  });

  testWidgets('回到前台重新藏起系统栏', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      disposeAfter(tester);

      await tester.pumpWidget(wrap(enabled: true));
      await tester.pumpAndSettle();
      expect(modes, <String>['SystemUiMode.immersiveSticky']);

      await sendLifecycle(tester, 'paused');
      await sendLifecycle(tester, 'resumed');
      expect(modes, <String>[
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.immersiveSticky',
      ]);
    });
  });

  testWidgets('非 Android 平台不动系统栏', (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      disposeAfter(tester);

      await tester.pumpWidget(wrap(enabled: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(modes, isEmpty);
    });
  });
}
