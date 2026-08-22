import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/reader_volume_keys.dart';

const MethodChannel _channel = MethodChannel(
  'app.lightnovel.shelf/reader_volume_keys',
);
const StandardMethodCodec _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<bool> writes = <bool>[];
  var failNextWrite = false;

  setUp(() {
    writes.clear();
    failNextWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method != 'setEnabled') return null;
          if (failNextWrite) {
            failNextWrite = false;
            throw PlatformException(code: 'boom');
          }
          writes.add(call.arguments as bool);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// 原生侧的回调都从平台通道进来，测试里照同一条路径推消息。
  ///
  /// 直接交给 handler，不走 `channelBuffers`：缓冲区的 drain 循环挂在建起 dispatcher
  /// 单例的那一局测试的 zone 上，换局之后消息里的 `await` 再也不会往下走。
  Future<void> sendFromPlatform(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
  }

  Future<void> sendLifecycle(WidgetTester tester, String state) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage('AppLifecycleState.$state'),
          (_) {},
        );
    await tester.pumpAndSettle();
  }

  /// [nested] 再套一个 listener，用来在开关值不变的情况下触发一次刷新。
  Widget wrap({
    required bool enabled,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    bool nested = false,
  }) {
    Widget child = const Scaffold(body: SizedBox.expand());
    if (nested) {
      child = ReaderVolumeKeyListener(
        enabled: enabled,
        onPrevious: () {},
        onNext: () {},
        child: child,
      );
    }
    return MaterialApp(
      navigatorObservers: <NavigatorObserver>[readerVolumeKeyRouteObserver],
      home: ReaderVolumeKeyListener(
        enabled: enabled,
        onPrevious: onPrevious ?? () {},
        onNext: onNext ?? () {},
        child: child,
      ),
    );
  }

  /// dispatcher 是单例：先挂一次 listener 把它连同平台通道的 handler 建起来，
  /// 再让它忘掉上一个用例留下的“已知状态”，否则本用例的首次下发会被去重掉。
  /// 用例结束时必须拆掉 widget 树，否则没 dispose 的 listener 会留在单例里继续算数。
  Future<void> reset(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(wrap(enabled: false));
    await tester.pumpAndSettle();
    await sendFromPlatform('resync');
    await tester.pumpAndSettle();
    writes.clear();
  }

  testWidgets('挂载开启时下发 true，卸载后下发 false', (tester) async {
    await reset(tester);

    await tester.pumpWidget(wrap(enabled: true));
    await tester.pumpAndSettle();
    expect(writes, <bool>[true]);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(writes, <bool>[true, false]);
  });

  testWidgets('设置关闭时不打开原生开关', (tester) async {
    await reset(tester);

    await tester.pumpWidget(wrap(enabled: false));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
  });

  testWidgets('音量键上下分别翻前后一页', (tester) async {
    await reset(tester);
    var previous = 0;
    var next = 0;

    await tester.pumpWidget(
      wrap(
        enabled: true,
        onPrevious: () => previous++,
        onNext: () => next++,
      ),
    );
    await tester.pumpAndSettle();

    await sendFromPlatform('onVolumeKey', 'down');
    await sendFromPlatform('onVolumeKey', 'up');
    await tester.pumpAndSettle();

    expect(next, 1);
    expect(previous, 1);
  });

  testWidgets('被弹层盖住时交还音量键，弹层关掉再拿回来', (tester) async {
    await reset(tester);
    var turns = 0;

    await tester.pumpWidget(
      wrap(enabled: true, onPrevious: () => turns++, onNext: () => turns++),
    );
    await tester.pumpAndSettle();
    expect(writes, <bool>[true]);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showModalBottomSheet<void>(
        context: navigator.context,
        builder: (_) => const SizedBox(height: 120),
      ),
    );
    await tester.pumpAndSettle();
    expect(writes, <bool>[true, false]);

    await sendFromPlatform('onVolumeKey', 'down');
    await tester.pumpAndSettle();
    expect(turns, 0);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(writes, <bool>[true, false, true]);

    await sendFromPlatform('onVolumeKey', 'down');
    await tester.pumpAndSettle();
    expect(turns, 1);
  });

  testWidgets('切到后台交还音量键，回前台再拿回来', (tester) async {
    await reset(tester);

    await tester.pumpWidget(wrap(enabled: true));
    await tester.pumpAndSettle();
    expect(writes, <bool>[true]);

    await sendLifecycle(tester, 'paused');
    expect(writes, <bool>[true, false]);

    await sendLifecycle(tester, 'resumed');
    expect(writes, <bool>[true, false, true]);
  });

  testWidgets('下发失败后下一次刷新重发同一个值', (tester) async {
    await reset(tester);
    failNextWrite = true;

    await tester.pumpWidget(wrap(enabled: true));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);

    // 原生状态无从得知，之后任何一次刷新都要把 true 再发一遍，否则这一整局都失效。
    await tester.pumpWidget(wrap(enabled: true, nested: true));
    await tester.pumpAndSettle();
    expect(writes, <bool>[true]);
  });

  testWidgets('原生要求 resync 时重发当前状态', (tester) async {
    await reset(tester);

    await tester.pumpWidget(wrap(enabled: true));
    await tester.pumpAndSettle();
    expect(writes, <bool>[true]);

    await sendFromPlatform('resync');
    await tester.pumpAndSettle();
    expect(writes, <bool>[true, true]);
  });
}
