import 'dart:async';

/// 串行化写入队列，旧请求不会覆盖新值。[schedule] 合并防抖窗口内的多次更新，
/// [commit] 按调用顺序立即入队，[flush] 等待在途写入落地。
///
/// 指纹相同的连续写会被跳过。
class DebouncedWriteQueue<T> {
  DebouncedWriteQueue(
    this._persist, {
    this.delay = const Duration(milliseconds: 450),
    String Function(T value)? fingerprint,
  }) : _fingerprint = fingerprint ?? ((T value) => '$value');

  final FutureOr<void> Function(T value) _persist;

  /// 防抖窗口：窗口内多次上报只写最后一次。
  final Duration delay;
  final String Function(T value) _fingerprint;

  T? _pending;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  String? _lastSuccessfulFingerprint;

  void schedule(T value) {
    _pending = value;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      final value = _pending;
      _pending = null;
      if (value != null) unawaited(_enqueue(value).catchError((Object _) {}));
    });
  }

  Future<void> commit(T value) async {
    _takePending();
    await _enqueue(value).catchError((Object _) {});
  }

  Future<void> flush() async {
    await _takePending()?.catchError((Object _) {});
    await _tail;
  }

  Future<void> dispose() => flush();

  Future<void>? _takePending() {
    _timer?.cancel();
    _timer = null;
    final value = _pending;
    if (value == null) return null;
    _pending = null;
    return _enqueue(value);
  }

  Future<void> _enqueue(T value) {
    final fingerprint = _fingerprint(value);
    final operation = _tail.then((_) async {
      if (fingerprint == _lastSuccessfulFingerprint) return;
      await _persist(value);
      _lastSuccessfulFingerprint = fingerprint;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
