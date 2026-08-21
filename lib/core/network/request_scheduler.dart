import 'dart:async';

import 'api_error.dart';

/// 交互请求优先于预加载。
enum RequestPriority { interactive, preload }

/// 取消令牌，语义同 `AbortSignal`。
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
}

class _PendingRequest<T> {
  _PendingRequest(this.operation, this.priority, this.completer);

  final Future<T> Function() operation;
  final RequestPriority priority;
  final Completer<T> completer;
  void Function()? cleanup;
}

/// 与服务端限流约定一致：5.5 秒窗口内最多 9 个请求。
class RateLimitRequestScheduler {
  RateLimitRequestScheduler({
    this.maxRequests = 9,
    this.window = const Duration(milliseconds: 5500),
  });

  final int maxRequests;
  final Duration window;

  final List<DateTime> _timestamps = <DateTime>[];
  final List<_PendingRequest<dynamic>> _pending = <_PendingRequest<dynamic>>[];
  bool _processing = false;

  Future<T> add<T>(
    Future<T> Function() operation, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) {
    if (cancelToken?.isCancelled ?? false) {
      return Future<T>.error(const RequestCancelledError());
    }

    final completer = Completer<T>();
    final pending = _PendingRequest<T>(operation, priority, completer);

    if (cancelToken != null) {
      void onCancel() {
        if (!_pending.remove(pending)) return;
        if (!completer.isCompleted) {
          completer.completeError(const RequestCancelledError());
        }
      }

      cancelToken.addListener(onCancel);
      pending.cleanup = () => cancelToken.removeListener(onCancel);
    }

    _pending.add(pending);
    unawaited(_process());
    return completer.future;
  }

  Future<void> _process() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_pending.isNotEmpty) {
        final now = DateTime.now();
        _timestamps.removeWhere((stamp) => now.difference(stamp) >= window);

        if (_timestamps.length >= maxRequests) {
          final oldest = _timestamps.first;
          final wait = window - now.difference(oldest);
          await Future<void>.delayed(
            wait.isNegative ? const Duration(milliseconds: 1) : wait,
          );
          continue;
        }

        final index = _pending.indexWhere(
          (request) => request.priority == RequestPriority.interactive,
        );
        final pending = _pending.removeAt(index >= 0 ? index : 0);
        pending.cleanup?.call();
        _timestamps.add(DateTime.now());
        unawaited(_run(pending));
      }
    } finally {
      _processing = false;
      if (_pending.isNotEmpty) unawaited(_process());
    }
  }

  Future<void> _run(_PendingRequest<dynamic> pending) async {
    try {
      final value = await pending.operation();
      if (!pending.completer.isCompleted) pending.completer.complete(value);
    } catch (error, stackTrace) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
  }
}
