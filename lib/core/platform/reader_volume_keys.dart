import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const OptionalMethodChannel _readerVolumeKeyChannel = OptionalMethodChannel(
  'app.lightnovel.shelf/reader_volume_keys',
);

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
    with WidgetsBindingObserver {
  bool _resumed = true;

  bool get _enabled => widget.enabled && _resumed;

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
  Future<void> _platformWrite = Future<void>.value();

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
    _platformWrite = _platformWrite.then(
      (_) => _setPlatformEnabled(enabled),
      onError: (_) => _setPlatformEnabled(enabled),
    );
  }

  Future<void> _setPlatformEnabled(bool enabled) async {
    await _readerVolumeKeyChannel.invokeMethod<void>('setEnabled', enabled);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onVolumeKey' || call.arguments is! String) return;
    for (final listener in _listeners.reversed) {
      if (!listener._enabled) continue;
      listener._handle(call.arguments as String);
      return;
    }
  }
}
