import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/async/debounced_write_queue.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/repositories/read_position_cache.dart';
import 'reader_position.dart';

/// 两个阅读器共用的阅读进度写入：合并防抖窗口内的上报，切章前提交，退到后台时
/// 落盘在途的写。
class ReaderProgressController {
  ReaderProgressController({required ApiClient api, required int bookId})
    : _api = api,
      _bookId = bookId {
    _queue = DebouncedWriteQueue<ReaderRestorePosition>(
      _persist,
      fingerprint: (position) => '${position.chapterId}:${position.position}',
    );
    _lifecycle = AppLifecycleListener(onPause: () => unawaited(flush()));
  }

  final ApiClient _api;
  final int _bookId;
  late final DebouncedWriteQueue<ReaderRestorePosition> _queue;
  late final AppLifecycleListener _lifecycle;

  /// 阅读中持续上报。先写进程内缓存，详情页与书架无需等待服务端往返即可读到最新进度。
  void stage(int chapterId, String position) {
    ReadPositionCache.stage(
      _bookId,
      BookReadPosition(
        chapterId: chapterId,
        position: position,
        readAt: DateTime.now(),
      ),
    );
    _queue.schedule(
      ReaderRestorePosition(chapterId: chapterId, position: position),
    );
  }

  Future<void> commit(int chapterId, String position) => _queue.commit(
    ReaderRestorePosition(chapterId: chapterId, position: position),
  );

  Future<void> flush() => _queue.flush();

  Future<void> dispose() {
    _lifecycle.dispose();
    return _queue.dispose();
  }

  Future<void> _persist(ReaderRestorePosition position) async {
    try {
      await _api.saveReadPosition(
        bookId: _bookId,
        chapterId: position.chapterId,
        position: position.position,
      );
    } catch (_) {
      // 进度写入失败不打断阅读，下一次上报会重试。
    }
  }
}
