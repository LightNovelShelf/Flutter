import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const OptionalMethodChannel _readerVolumeKeyChannel = OptionalMethodChannel(
  'app.lightnovel.shelf/reader_volume_keys',
);

/// 挂在根 `Navigator` 上，让阅读器知道自己被弹层或新页面盖住了。
/// 盖住时要把音量键还给系统，否则脚注弹层上按音量既不翻页也不调音量。
final RouteObserver<Route<dynamic>> readerVolumeKeyRouteObserver =
    RouteObserver<Route<dynamic>>();

/// 在阅读器可见且设置开启时，把 Android 音量键转成前后翻页操作。
class ReaderVolumeKeyListener extends StatefulWidget {
  const ReaderVolumeKeyListener({
    super.key,
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;

  @override
  State<ReaderVolumeKeyListener> createState() =>
      _ReaderVolumeKeyListenerState();
}

class _ReaderVolumeKeyListenerState extends State<ReaderVolumeKeyListener>
    with WidgetsBindingObserver, RouteAware {
  bool _resumed = true;
  bool _covered = false;
  Route<dynamic>? _route;

  bool get _enabled => widget.enabled && _resumed && !_covered;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _resumed =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _ReaderVolumeKeyDispatcher.instance.attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    if (_route != null) readerVolumeKeyRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) readerVolumeKeyRouteObserver.subscribe(this, route);
    _setCovered(route != null && !route.isCurrent);
  }

  @override
  void didUpdateWidget(ReaderVolumeKeyListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _ReaderVolumeKeyDispatcher.instance.refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_resumed == resumed) return;
    _resumed = resumed;
    _ReaderVolumeKeyDispatcher.instance.refresh();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool covered) {
    if (_covered == covered) return;
    _covered = covered;
    _ReaderVolumeKeyDispatcher.instance.refresh();
  }

  void _handle(String key) {
    if (!_enabled || !mounted) return;
    if (key == 'up') {
      widget.onPrevious();
    } else if (key == 'down') {
      widget.onNext();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) readerVolumeKeyRouteObserver.unsubscribe(this);
    _ReaderVolumeKeyDispatcher.instance.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReaderVolumeKeyDispatcher {
  _ReaderVolumeKeyDispatcher._() {
    _readerVolumeKeyChannel.setMethodCallHandler(_handleMethodCall);
  }

  static final _ReaderVolumeKeyDispatcher instance =
      _ReaderVolumeKeyDispatcher._();

  final List<_ReaderVolumeKeyListenerState> _listeners =
      <_ReaderVolumeKeyListenerState>[];
  bool _platformStateKnown = false;
  bool _requestedEnabled = false;
  bool _writing = false;
  bool? _pendingWrite;

  /// 原生侧重建一次就换一代，正在飞的下发到下一轮自己退场。
  int _generation = 0;

  void attach(_ReaderVolumeKeyListenerState listener) {
    _listeners.add(listener);
    refresh();
  }

  void detach(_ReaderVolumeKeyListenerState listener) {
    _listeners.remove(listener);
    refresh();
  }

  void refresh() {
    final enabled = _listeners.any((listener) => listener._enabled);
    if (_platformStateKnown && _requestedEnabled == enabled) return;
    _platformStateKnown = true;
    _requestedEnabled = enabled;
    // 下发要串行，否则先后两次开关到了原生侧可能反序，开关状态与阅读器对不上。
    _pendingWrite = enabled;
    if (!_writing) unawaited(_drainWrites(_generation));
  }

  Future<void> _drainWrites(int generation) async {
    _writing = true;
    while (_pendingWrite != null && generation == _generation) {
      final enabled = _pendingWrite!;
      _pendingWrite = null;
      try {
        await _readerVolumeKeyChannel.invokeMethod<void>('setEnabled', enabled);
      } catch (_) {
        // 写失败后原生侧的状态无从得知，忘掉这次请求，让下一次 refresh 重发。
        if (_pendingWrite == null && _requestedEnabled == enabled) {
          _platformStateKnown = false;
        }
      }
    }
    // 换代之后这一轮已经不作数，_writing 归新的那一轮管。
    if (generation == _generation) _writing = false;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'resync') {
      // 原生侧刚重建：排队里的下发全作废，状态重新算一遍再发。
      _generation++;
      _writing = false;
      _pendingWrite = null;
      _platformStateKnown = false;
      refresh();
      return;
    }
    if (call.method != 'onVolumeKey' || call.arguments is! String) return;
    for (final listener in _listeners.reversed) {
      if (!listener._enabled) continue;
      listener._handle(call.arguments as String);
      return;
    }
  }
}
