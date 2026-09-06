import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'direct_message_realtime.dart';
import 'profile_repository.dart';

/// 推送到达后延迟这么久再对账，连续到达的消息只换来一次资料请求。
const Duration _reconcileDelay = Duration(milliseconds: 400);

/// 社区入口的未读角标：通知未读 + 私信未读。
///
/// 私信推送不带未读数（阅读者的未读是私有状态，且乱序到达的旧事件会把它算错），
/// 收到推送后统一按服务端计数对账。自己在别的端读消息时同样会收到已读回执，走同一条路径。
class CommunityUnreadCountController extends Notifier<int> {
  bool _disposed = false;
  Timer? _timer;
  bool _running = false;

  /// 对账途中又收到推送，跑完当前一轮再补一轮。
  bool _dirty = false;

  @override
  int build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen(directMessageEventProvider, (_, next) {
      // 拉黑状态变化不影响未读数。
      if (next.value is DirectMessageBlockChanged) return;
      _schedule();
    });
    final profile = ref.watch(profileProvider).value;
    return (profile?.unreadNotificationCount ?? 0) +
        (profile?.unreadDirectMessageCount ?? 0);
  }

  void _schedule() {
    if (_timer?.isActive ?? false) return;
    // Timer 不在 ref.onDispose 里取消：build 每次重跑都会触发一次 onDispose，
    // 那会把上一次推送排的对账取消掉。回调里查 _disposed。
    _timer = Timer(_reconcileDelay, () {
      _timer = null;
      unawaited(reconcile());
    });
  }

  /// 立即按服务端资料对账，应用恢复前台时调用。
  Future<void> reconcile() async {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    try {
      do {
        // 先清标记再请求，保证至少有一次请求发生在最新推送之后。
        _dirty = false;
        try {
          await ref.read(profileProvider.notifier).refreshQuietly();
        } catch (_) {
          // 角标对账失败保持旧值，下一次推送或回到前台时会再对一次。
        }
      } while (_dirty && !_disposed);
    } finally {
      _running = false;
    }
  }
}

final NotifierProvider<CommunityUnreadCountController, int>
communityUnreadCountProvider =
    NotifierProvider<CommunityUnreadCountController, int>(
      CommunityUnreadCountController.new,
    );
