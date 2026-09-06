import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/user_avatar.dart';
import 'direct_message_providers.dart';

/// 相邻消息间隔超过它就插一条时间分隔。
const Duration _timeGap = Duration(minutes: 5);

/// 与某个用户的一对一会话。
class DirectChatScreen extends ConsumerStatefulWidget {
  const DirectChatScreen({super.key, required this.peerId});

  final int peerId;

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _controller = ScrollController();
  final TextEditingController _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 反向列表里「更远」的一端是更早的消息。
    _controller.attachPrefetch(
      onLoadMore: () =>
          ref.read(directChatProvider(widget.peerId).notifier).loadOlder(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(directChatProvider(widget.peerId).notifier).load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final controller = ref.read(directChatProvider(widget.peerId).notifier);
    final text = normalizeDirectMessageContent(_input.text);
    if (text.isEmpty) return;
    if (text.runes.length > directMessageMaxLength) {
      showAppSnackBar(context, '消息最多 $directMessageMaxLength 个字符。');
      return;
    }
    controller.send(text);
    _input.clear();
  }

  Future<void> _toggleBlock(DirectChatState state) async {
    final controller = ref.read(directChatProvider(widget.peerId).notifier);
    if (!state.isBlockedByMe) {
      final confirmed = await showAppConfirm(
        context: context,
        title: '拉黑对方？',
        message: '拉黑后双方都无法再向对方发送私信，历史消息仍然保留。',
        confirmLabel: '拉黑',
        destructive: true,
      );
      if (!confirmed) return;
    }
    await controller.setBlocked(!state.isBlockedByMe);
  }

  @override
  Widget build(BuildContext context) {
    final peerId = widget.peerId;
    final state = ref.watch(directChatProvider(peerId));
    final controller = ref.read(directChatProvider(peerId).notifier);

    ref.listen(directChatProvider(peerId), (previous, next) {
      final notice = next.notice;
      if (notice == null ||
          previous == null ||
          next.noticeTag == previous.noticeTag) {
        return;
      }
      showAppSnackBar(context, notice);
    });

    final peer = state.peer;
    final title = peer == null
        ? '私信'
        : displayUserName(peer.userName, deleted: peer.isDeleted);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (peer != null && !peer.isDeleted)
            PopupMenuButton<int>(
              enabled: !state.blocking,
              onSelected: (_) => _toggleBlock(state),
              itemBuilder: (_) => <PopupMenuEntry<int>>[
                PopupMenuItem<int>(
                  value: 0,
                  child: Text(state.isBlockedByMe ? '取消拉黑' : '拉黑对方'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildBody(state, controller)),
          _Composer(
            input: _input,
            blockedReason: _blockedReason(state),
            enabled: state.canSend,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  String? _blockedReason(DirectChatState state) {
    if (state.canSend || state.loading) return null;
    if (state.isBlockedByMe) return '你已拉黑对方，取消拉黑后才能继续私信。';
    if (state.peer?.isDeleted ?? false) return '对方已注销，无法继续私信。';
    return '对方暂时无法接收你的私信。';
  }

  Widget _buildBody(DirectChatState state, DirectChatController controller) {
    if (state.loading && state.messages.isEmpty) {
      final error = state.error;
      if (error != null) {
        return ErrorStateView(message: error, onRetry: controller.load);
      }
      return const Center(child: CircularProgressIndicator());
    }
    final error = state.error;
    if (error != null && state.messages.isEmpty && state.pending.isEmpty) {
      return ErrorStateView(message: error, onRetry: controller.load);
    }

    final rows = _buildRows(state);
    if (rows.isEmpty) {
      return const EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: '还没有消息',
        description: '发出第一条消息，开始你们的对话。',
      );
    }

    return ListView.builder(
      controller: _controller,
      reverse: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: rows.length + 1,
      itemBuilder: (_, index) {
        // 反向列表的最后一项在最上方，用来提示还有更早的消息。
        if (index == rows.length) {
          if (!state.hasMore && state.loadMoreError == null) {
            return const SizedBox(height: 8);
          }
          return ListFooterStatus(
            loading: state.loadingMore,
            hasMore: state.hasMore,
            endLabel: '没有更早的消息了',
            error: state.loadMoreError,
            onRetry: controller.loadOlder,
          );
        }
        return _buildRow(rows[rows.length - 1 - index], state, controller);
      },
    );
  }

  Widget _buildRow(
    _ChatRow row,
    DirectChatState state,
    DirectChatController controller,
  ) => switch (row) {
    _TimeRow(:final time) => _TimeSeparator(time: time),
    _MessageRow(:final message) => _MessageBubble(
      content: message.content,
      createdAt: message.createdAt,
      isMine: message.senderId != widget.peerId,
      peer: state.peer,
      // 只有最后一条自己发的消息显示送达状态，逐条显示会糊满整屏。
      status: message.id == _lastOwnMessageId(state)
          ? (state.peerLastReadMessageId >= message.id ? '已读' : '已送达')
          : null,
    ),
    _PendingRow(:final pending) => _PendingBubble(
      pending: pending,
      onRetry: () => controller.retry(pending.clientMessageId),
      onDiscard: () => controller.discard(pending.clientMessageId),
    ),
  };

  int _lastOwnMessageId(DirectChatState state) {
    for (final message in state.messages.reversed) {
      if (message.senderId != widget.peerId) return message.id;
    }
    return 0;
  }

  List<_ChatRow> _buildRows(DirectChatState state) {
    final rows = <_ChatRow>[];
    DateTime? previous;
    for (final message in state.messages) {
      if (previous == null ||
          message.createdAt.difference(previous) > _timeGap) {
        rows.add(_TimeRow(message.createdAt));
      }
      previous = message.createdAt;
      rows.add(_MessageRow(message));
    }
    for (final pending in state.pending) {
      if (previous == null ||
          pending.createdAt.difference(previous) > _timeGap) {
        rows.add(_TimeRow(pending.createdAt));
      }
      previous = pending.createdAt;
      rows.add(_PendingRow(pending));
    }
    return rows;
  }
}

sealed class _ChatRow {
  const _ChatRow();
}

class _TimeRow extends _ChatRow {
  const _TimeRow(this.time);

  final DateTime time;
}

class _MessageRow extends _ChatRow {
  const _MessageRow(this.message);

  final DirectMessageItem message;
}

class _PendingRow extends _ChatRow {
  const _PendingRow(this.pending);

  final PendingDirectMessage pending;
}

class _TimeSeparator extends StatelessWidget {
  const _TimeSeparator({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Text(
        formatDateTime(time.toLocal()),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.content,
    required this.createdAt,
    required this.isMine,
    required this.peer,
    this.status,
  });

  final String content;
  final DateTime createdAt;
  final bool isMine;
  final DirectMessagePeer? peer;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = this.status;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: isMine
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SelectableText(
        content,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: isMine ? colors.onPrimaryContainer : colors.onSurface,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine && peer != null) ...<Widget>[
            UserAvatar(
              url: peer!.avatar,
              name: displayUserName(peer!.userName, deleted: peer!.isDeleted),
              size: 34,
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: <Widget>[
              bubble,
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingBubble extends StatelessWidget {
  const _PendingBubble({
    required this.pending,
    required this.onRetry,
    required this.onDiscard,
  });

  final PendingDirectMessage pending;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (!pending.failed)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
                ),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  pending.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (pending.failed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      pending.error ?? '发送失败',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: colors.error),
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('重试')),
                  TextButton(onPressed: onDiscard, child: const Text('删除')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.blockedReason,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController input;
  final String? blockedReason;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reason = blockedReason;
    return Material(
      color: colors.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: reason != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: input,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          hintText: '发消息…',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: enabled ? onSend : null,
                      icon: const Icon(Icons.send),
                      tooltip: '发送',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
