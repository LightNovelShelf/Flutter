import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/async/serial_queue.dart';
import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/direct_message_realtime.dart';

const int directConversationPageSize = 20;
const int directMessagePageSize = 30;

/// 与 db.direct_message 的 char_length 约束一致，按 Unicode 标量值计数。
const int directMessageMaxLength = 2000;

/// 推送到达后延迟这么久再拉会话列表，连发的消息只换来一次请求。
const Duration _reconcileDelay = Duration(milliseconds: 400);

final Random _random = Random.secure();

/// 客户端幂等键。重发必须复用同一个，否则服务端会当成新消息再存一条。
String newClientMessageId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// 与服务端一致的正文规范化。本地不做同样处理时，重发的正文会和幂等键对不上，服务端返回 409。
String normalizeDirectMessageContent(String content) =>
    content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

String describeDirectMessageError(
  Object error, {
  String fallback = '私信暂时不可用。',
}) => describeApiError(error, fallback: fallback, normalize: true);

@immutable
class DirectConversationListState {
  const DirectConversationListState({
    this.items = const <DirectConversationItem>[],
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.hasMore = false,
    this.nextBeforeMessageId = 0,
  });

  final List<DirectConversationItem> items;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;
  final bool hasMore;
  final int nextBeforeMessageId;

  static const Object _keep = Object();

  DirectConversationListState copyWith({
    List<DirectConversationItem>? items,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _keep,
    Object? loadMoreError = _keep,
    bool? hasMore,
    int? nextBeforeMessageId,
  }) => DirectConversationListState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _keep) ? this.error : error as String?,
    loadMoreError: identical(loadMoreError, _keep)
        ? this.loadMoreError
        : loadMoreError as String?,
    hasMore: hasMore ?? this.hasMore,
    nextBeforeMessageId: nextBeforeMessageId ?? this.nextBeforeMessageId,
  );
}

/// 会话列表。推送只够更新已在列表里的会话，未读数与新会话统一按去抖节奏问服务端。
class DirectConversationListController
    extends Notifier<DirectConversationListState> {
  int _generation = 0;
  bool _disposed = false;
  bool _scheduled = false;

  @override
  DirectConversationListState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.watch(apiClientProvider);
    ref.listen(directMessageEventProvider, (_, next) {
      final event = next.value;
      if (event != null) _apply(event);
    });
    unawaited(Future<void>.microtask(() => _load(preserve: false)));
    return const DirectConversationListState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> refresh() => _load(preserve: true);

  Future<void> retry() => _load(preserve: false);

  Future<void> _load({required bool preserve}) async {
    if (_disposed) return;
    final generation = ++_generation;
    state = preserve
        ? state.copyWith(
            refreshing: true,
            loadingMore: false,
            error: null,
            loadMoreError: null,
          )
        : const DirectConversationListState();
    try {
      final page = await _api.getDirectConversations(
        size: directConversationPageSize,
      );
      if (_isStale(generation)) return;
      _applyFirstPage(page);
    } catch (error) {
      if (isCancellation(error) || _isStale(generation)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: describeDirectMessageError(error, fallback: '无法加载私信。'),
      );
    }
  }

  /// 首页合并进已加载的列表：翻过页的用户刷新后不会被打回第一页。
  void _applyFirstPage(DirectConversationsPage page) {
    final merged = _merge(state.items, page.items);
    state = state.copyWith(
      items: merged,
      loading: false,
      refreshing: false,
      error: null,
      loadMoreError: null,
      // 列表比首页长说明还加载过更旧的页，「更旧的还有没有」以旧状态为准。
      hasMore: merged.length > page.items.length ? state.hasMore : page.hasMore,
      nextBeforeMessageId: merged.isEmpty ? 0 : merged.last.lastMessage.id,
    );
  }

  Future<void> loadMore() async {
    final current = state;
    if (current.loading ||
        current.refreshing ||
        current.loadingMore ||
        !current.hasMore ||
        current.nextBeforeMessageId <= 0) {
      return;
    }
    final generation = ++_generation;
    state = current.copyWith(loadingMore: true, loadMoreError: null);
    try {
      final page = await _api.getDirectConversations(
        beforeMessageId: current.nextBeforeMessageId,
        size: directConversationPageSize,
      );
      if (_isStale(generation)) return;
      final merged = _merge(state.items, page.items);
      state = state.copyWith(
        items: merged,
        loadingMore: false,
        hasMore: page.hasMore,
        nextBeforeMessageId: merged.isEmpty ? 0 : merged.last.lastMessage.id,
      );
    } catch (error) {
      if (isCancellation(error) || _isStale(generation)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeDirectMessageError(error, fallback: '无法加载更多会话。'),
      );
    }
  }

  void _apply(DirectMessageEvent event) {
    switch (event) {
      case DirectMessageReceived(:final peerId, :final message):
        _updateConversation(
          peerId,
          (item) => message.id > item.lastMessage.id
              ? item.copyWith(lastMessage: message)
              : item,
        );
        // 未读数和新会话只能问服务端。
        _schedule();
      case DirectMessageReadReceipt(
        :final peerId,
        :final readerId,
        :final throughMessageId,
      ):
        if (readerId == peerId) {
          _updateConversation(
            peerId,
            (item) => item.copyWith(
              peerLastReadMessageId: max(
                item.peerLastReadMessageId,
                throughMessageId,
              ),
            ),
          );
          return;
        }
        // 自己（可能在别的端）读了消息，未读数重新对账。
        _schedule();
      case DirectMessageBlockChanged(
        :final peerId,
        :final isBlockedByMe,
        :final canSend,
      ):
        _updateConversation(
          peerId,
          (item) =>
              item.copyWith(isBlockedByMe: isBlockedByMe, canSend: canSend),
        );
    }
  }

  void _updateConversation(
    int peerId,
    DirectConversationItem Function(DirectConversationItem item) update,
  ) {
    final index = state.items.indexWhere((item) => item.peer.id == peerId);
    if (index < 0) return;
    final items = List<DirectConversationItem>.of(state.items);
    items[index] = update(items[index]);
    items.sort((a, b) => b.lastMessage.id.compareTo(a.lastMessage.id));
    state = state.copyWith(items: items);
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    Future<void>.delayed(_reconcileDelay, () {
      _scheduled = false;
      if (_disposed) return;
      if (state.loading || state.refreshing) {
        // 正在跑的那一轮可能早于这条推送，等它结束再补一轮。
        _schedule();
        return;
      }
      unawaited(refresh());
    });
  }

  /// 按对方 ID 合并，已在列表里的会话用新数据替换，整体按最后一条消息倒序。
  static List<DirectConversationItem> _merge(
    List<DirectConversationItem> existing,
    List<DirectConversationItem> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final byPeer = <int, DirectConversationItem>{
      for (final item in existing) item.peer.id: item,
      for (final item in incoming) item.peer.id: item,
    };
    final merged = byPeer.values.toList(growable: false)
      ..sort((a, b) => b.lastMessage.id.compareTo(a.lastMessage.id));
    return merged;
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
}

final NotifierProvider<
  DirectConversationListController,
  DirectConversationListState
>
directConversationListProvider =
    NotifierProvider<
      DirectConversationListController,
      DirectConversationListState
    >(DirectConversationListController.new, isAutoDispose: true);

/// 待发送的消息。服务端确认后从 pending 移除，改由确认后的消息渲染。
@immutable
class PendingDirectMessage {
  const PendingDirectMessage({
    required this.clientMessageId,
    required this.content,
    required this.createdAt,
    this.failed = false,
    this.error,
  });

  final String clientMessageId;
  final String content;
  final DateTime createdAt;
  final bool failed;
  final String? error;

  PendingDirectMessage copyWith({required bool failed, String? error}) =>
      PendingDirectMessage(
        clientMessageId: clientMessageId,
        content: content,
        createdAt: createdAt,
        failed: failed,
        error: error,
      );
}

@immutable
class DirectChatState {
  const DirectChatState({
    this.peer,
    this.messages = const <DirectMessageItem>[],
    this.pending = const <PendingDirectMessage>[],
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.hasMore = false,
    this.nextBeforeMessageId = 0,
    this.historyInitialized = false,
    this.myLastReadMessageId = 0,
    this.peerLastReadMessageId = 0,
    this.isBlockedByMe = false,
    this.canSend = false,
    this.blocking = false,
    this.notice,
    this.noticeTag = 0,
  });

  final DirectMessagePeer? peer;

  /// 按 id 升序。
  final List<DirectMessageItem> messages;
  final List<PendingDirectMessage> pending;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;
  final bool hasMore;
  final int nextBeforeMessageId;
  final bool historyInitialized;
  final int myLastReadMessageId;
  final int peerLastReadMessageId;
  final bool isBlockedByMe;
  final bool canSend;

  /// 拉黑提交中，菜单项在此期间禁用。
  final bool blocking;

  /// 一次性提示，[noticeTag] 递增用于区分文案相同的重复失败。
  final String? notice;
  final int noticeTag;

  static const Object _keep = Object();

  DirectChatState copyWith({
    DirectMessagePeer? peer,
    List<DirectMessageItem>? messages,
    List<PendingDirectMessage>? pending,
    bool? loading,
    bool? loadingMore,
    Object? error = _keep,
    Object? loadMoreError = _keep,
    bool? hasMore,
    int? nextBeforeMessageId,
    bool? historyInitialized,
    int? myLastReadMessageId,
    int? peerLastReadMessageId,
    bool? isBlockedByMe,
    bool? canSend,
    bool? blocking,
    String? notice,
    int? noticeTag,
  }) => DirectChatState(
    peer: peer ?? this.peer,
    messages: messages ?? this.messages,
    pending: pending ?? this.pending,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _keep) ? this.error : error as String?,
    loadMoreError: identical(loadMoreError, _keep)
        ? this.loadMoreError
        : loadMoreError as String?,
    hasMore: hasMore ?? this.hasMore,
    nextBeforeMessageId: nextBeforeMessageId ?? this.nextBeforeMessageId,
    historyInitialized: historyInitialized ?? this.historyInitialized,
    myLastReadMessageId: myLastReadMessageId ?? this.myLastReadMessageId,
    peerLastReadMessageId: peerLastReadMessageId ?? this.peerLastReadMessageId,
    isBlockedByMe: isBlockedByMe ?? this.isBlockedByMe,
    canSend: canSend ?? this.canSend,
    blocking: blocking ?? this.blocking,
    notice: notice ?? this.notice,
    noticeTag: noticeTag ?? this.noticeTag,
  );
}

/// 单个会话。消息按 id 升序保存，发送与重发共用一条串行队列，保证提交顺序即点击顺序。
class DirectChatController extends Notifier<DirectChatState> {
  DirectChatController(this.peerId);

  final int peerId;

  final SerialQueue _sendQueue = SerialQueue();

  int _generation = 0;
  bool _disposed = false;
  bool _marking = false;
  bool _markDirty = false;

  @override
  DirectChatState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.watch(apiClientProvider);
    ref.listen(directMessageEventProvider, (_, next) {
      final event = next.value;
      if (event != null && event.peerId == peerId) _apply(event);
    });
    unawaited(Future<void>.microtask(load));
    return const DirectChatState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> load() async {
    if (_disposed) return;
    final preserveHistoryCursor = state.historyInitialized;
    final generation = ++_generation;
    state = state.copyWith(
      loading: state.messages.isEmpty,
      loadingMore: false,
      error: null,
    );
    try {
      final page = await _api.getDirectMessages(
        peerUserId: peerId,
        size: directMessagePageSize,
      );
      if (_isStale(generation)) return;
      final messages = _mergeMessages(state.messages, page.items);
      state = state.copyWith(
        peer: page.peer,
        messages: messages,
        pending: _withoutConfirmed(state.pending, page.items),
        loading: false,
        error: null,
        // 重新对账时保留已加载范围的游标，避免新消息把分页起点前移。
        hasMore: preserveHistoryCursor ? state.hasMore : page.hasMore,
        nextBeforeMessageId: preserveHistoryCursor
            ? state.nextBeforeMessageId
            : page.nextBeforeMessageId,
        historyInitialized: true,
        myLastReadMessageId: max(
          state.myLastReadMessageId,
          page.myLastReadMessageId,
        ),
        peerLastReadMessageId: max(
          state.peerLastReadMessageId,
          page.peerLastReadMessageId,
        ),
        isBlockedByMe: page.isBlockedByMe,
        canSend: page.canSend,
      );
      unawaited(markRead());
    } catch (error) {
      if (isCancellation(error) || _isStale(generation)) return;
      state = state.copyWith(
        loading: false,
        error: describeDirectMessageError(error, fallback: '无法加载私信。'),
      );
    }
  }

  Future<void> loadOlder() async {
    final current = state;
    if (current.loading ||
        current.loadingMore ||
        !current.hasMore ||
        current.nextBeforeMessageId <= 0) {
      return;
    }
    final generation = _generation;
    state = current.copyWith(loadingMore: true, loadMoreError: null);
    try {
      final page = await _api.getDirectMessages(
        peerUserId: peerId,
        beforeMessageId: current.nextBeforeMessageId,
        size: directMessagePageSize,
      );
      if (_isStale(generation)) return;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, page.items),
        loadingMore: false,
        hasMore: page.hasMore,
        nextBeforeMessageId: page.nextBeforeMessageId,
      );
    } catch (error) {
      if (isCancellation(error) || _isStale(generation)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeDirectMessageError(
          error,
          fallback: '无法加载更早的消息。',
        ),
      );
    }
  }

  /// 正文为空或超长时不入队，由调用方保证提示。
  void send(String content) {
    final text = normalizeDirectMessageContent(content);
    if (text.isEmpty) return;
    final pending = PendingDirectMessage(
      clientMessageId: newClientMessageId(),
      content: text,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      pending: <PendingDirectMessage>[...state.pending, pending],
    );
    unawaited(_submit(pending.clientMessageId));
  }

  void retry(String clientMessageId) => unawaited(_submit(clientMessageId));

  void discard(String clientMessageId) {
    state = state.copyWith(
      pending: state.pending
          .where((item) => item.clientMessageId != clientMessageId)
          .toList(growable: false),
    );
  }

  Future<void> _submit(String clientMessageId) => _sendQueue.add(() async {
    if (_disposed) return;
    final index = state.pending.indexWhere(
      (item) => item.clientMessageId == clientMessageId,
    );
    if (index < 0) return;
    final pending = state.pending[index];
    _updatePending(clientMessageId, failed: false);
    try {
      final result = await _api.sendDirectMessage(
        recipientUserId: peerId,
        clientMessageId: clientMessageId,
        content: pending.content,
      );
      if (_disposed) return;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, <DirectMessageItem>[
          result.message,
        ]),
        pending: state.pending
            .where((item) => item.clientMessageId != clientMessageId)
            .toList(growable: false),
        peerLastReadMessageId: max(
          state.peerLastReadMessageId,
          result.peerLastReadMessageId,
        ),
      );
    } catch (error) {
      if (_disposed) return;
      _updatePending(
        clientMessageId,
        failed: true,
        error: describeDirectMessageError(error, fallback: '消息没能发出去。'),
      );
    }
  });

  void _updatePending(
    String clientMessageId, {
    required bool failed,
    String? error,
  }) {
    final index = state.pending.indexWhere(
      (item) => item.clientMessageId == clientMessageId,
    );
    if (index < 0) return;
    final pending = List<PendingDirectMessage>.of(state.pending);
    pending[index] = pending[index].copyWith(failed: failed, error: error);
    state = state.copyWith(pending: pending);
  }

  /// 已读游标推到最后一条消息。服务端会把回执推回来，未读角标由它对账。
  Future<void> markRead() async {
    if (_marking) {
      _markDirty = true;
      return;
    }
    _marking = true;
    try {
      while (!_disposed) {
        _markDirty = false;
        final messages = state.messages;
        if (messages.isEmpty) break;
        final through = messages.last.id;
        if (through <= state.myLastReadMessageId) break;
        try {
          final result = await _api.markDirectMessagesRead(
            peerUserId: peerId,
            throughMessageId: through,
          );
          if (_disposed) break;
          state = state.copyWith(
            myLastReadMessageId: max(
              state.myLastReadMessageId,
              result.myLastReadMessageId,
            ),
          );
        } catch (_) {
          // 已读失败不打扰用户，下次进入会话或收到新消息时会再提交。
          break;
        }
        if (!_markDirty) break;
      }
    } finally {
      _marking = false;
    }
    if (_markDirty && !_disposed) unawaited(markRead());
  }

  Future<void> setBlocked(bool blocked) async {
    if (state.blocking) return;
    state = state.copyWith(blocking: true);
    try {
      final result = await _api.setDirectMessageBlock(
        userId: peerId,
        isBlocked: blocked,
      );
      if (_disposed) return;
      state = state.copyWith(
        blocking: false,
        isBlockedByMe: result.isBlockedByMe,
        canSend: result.canSend,
      );
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        blocking: false,
        notice: describeDirectMessageError(error, fallback: '操作没有生效。'),
        noticeTag: state.noticeTag + 1,
      );
    }
  }

  void _apply(DirectMessageEvent event) {
    switch (event) {
      case DirectMessageReceived(:final message):
        state = state.copyWith(
          messages: _mergeMessages(state.messages, <DirectMessageItem>[
            message,
          ]),
          pending: _withoutConfirmed(state.pending, <DirectMessageItem>[
            message,
          ]),
        );
        // 会话开着就直接读掉，未读数不必先涨再落。
        if (message.senderId == peerId) unawaited(markRead());
      case DirectMessageReadReceipt(:final readerId, :final throughMessageId):
        state = readerId == peerId
            ? state.copyWith(
                peerLastReadMessageId: max(
                  state.peerLastReadMessageId,
                  throughMessageId,
                ),
              )
            // 自己在别的端读的。
            : state.copyWith(
                myLastReadMessageId: max(
                  state.myLastReadMessageId,
                  throughMessageId,
                ),
              );
      case DirectMessageBlockChanged(:final isBlockedByMe, :final canSend):
        state = state.copyWith(isBlockedByMe: isBlockedByMe, canSend: canSend);
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  /// 按 id 升序合并去重。自己发的消息会分别从发送响应和推送到达，两条路径 id 相同。
  static List<DirectMessageItem> _mergeMessages(
    List<DirectMessageItem> existing,
    List<DirectMessageItem> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final byId = <int, DirectMessageItem>{
      for (final item in existing) item.id: item,
      for (final item in incoming) item.id: item,
    };
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    return merged;
  }

  /// 推送可能早于发送响应到达，确认过的幂等键要从待发送列表里摘掉。
  static List<PendingDirectMessage> _withoutConfirmed(
    List<PendingDirectMessage> pending,
    List<DirectMessageItem> confirmed,
  ) {
    if (pending.isEmpty || confirmed.isEmpty) return pending;
    final ids = <String>{for (final item in confirmed) item.clientMessageId};
    if (!pending.any((item) => ids.contains(item.clientMessageId))) {
      return pending;
    }
    return pending
        .where((item) => !ids.contains(item.clientMessageId))
        .toList(growable: false);
  }
}

final NotifierProviderFamily<DirectChatController, DirectChatState, int>
directChatProvider =
    NotifierProvider.family<DirectChatController, DirectChatState, int>(
      DirectChatController.new,
      isAutoDispose: true,
    );
