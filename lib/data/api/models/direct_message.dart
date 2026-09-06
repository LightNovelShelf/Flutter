import '../decode.dart';

/// Hub 响应走 gzip 通道，由服务端自己的序列化器写出，字段是 PascalCase；
/// 服务端推送走 SignalR 的 JSON 协议，字段被 camelCase 化。两种写法都试一次。
Object? _field(Map<String, dynamic> record, String name) {
  final Object? value = record[name];
  if (value != null) return value;
  return record['${name[0].toLowerCase()}${name.substring(1)}'];
}

class DirectMessagePeer {
  const DirectMessagePeer({
    required this.id,
    required this.userName,
    required this.avatar,
    required this.isDeleted,
  });

  final int id;
  final String userName;
  final String avatar;
  final bool isDeleted;

  static DirectMessagePeer decode(Object? value) {
    final record = asRecordOrEmpty(value);
    return DirectMessagePeer(
      id: asInt(_field(record, 'Id'), 0),
      userName: asStringOrEmpty(_field(record, 'UserName')),
      avatar: asStringOrEmpty(_field(record, 'Avatar')),
      isDeleted: asBool(_field(record, 'IsDeleted'), false),
    );
  }
}

class DirectMessageItem {
  const DirectMessageItem({
    required this.id,
    required this.clientMessageId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final String clientMessageId;
  final int senderId;
  final String content;
  final DateTime createdAt;

  static DirectMessageItem decode(Object? value) {
    final record = asRecordOrEmpty(value);
    return DirectMessageItem(
      id: asInt(_field(record, 'Id'), 0),
      clientMessageId: asStringOrEmpty(_field(record, 'ClientMessageId')),
      senderId: asInt(_field(record, 'SenderId'), 0),
      content: asStringOrEmpty(_field(record, 'Content')),
      createdAt: asDate(_field(record, 'CreatedAt')),
    );
  }

  /// 会话的最后一条消息在极端并发下可能取不到，此时整条会话不展示。
  static DirectMessageItem? decodeOrNull(Object? value) =>
      asRecordOrNull(value) == null ? null : decode(value);
}

class DirectConversationItem {
  const DirectConversationItem({
    required this.peer,
    required this.lastMessage,
    required this.unreadCount,
    required this.peerLastReadMessageId,
    required this.isBlockedByMe,
    required this.canSend,
  });

  final DirectMessagePeer peer;
  final DirectMessageItem lastMessage;
  final int unreadCount;
  final int peerLastReadMessageId;
  final bool isBlockedByMe;
  final bool canSend;

  DirectConversationItem copyWith({
    DirectMessageItem? lastMessage,
    int? unreadCount,
    int? peerLastReadMessageId,
    bool? isBlockedByMe,
    bool? canSend,
  }) => DirectConversationItem(
    peer: peer,
    lastMessage: lastMessage ?? this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    peerLastReadMessageId: peerLastReadMessageId ?? this.peerLastReadMessageId,
    isBlockedByMe: isBlockedByMe ?? this.isBlockedByMe,
    canSend: canSend ?? this.canSend,
  );

  static DirectConversationItem? decodeOrNull(Object? value) {
    final record = asRecordOrNull(value);
    if (record == null) return null;
    final lastMessage = DirectMessageItem.decodeOrNull(
      _field(record, 'LastMessage'),
    );
    if (lastMessage == null) return null;
    return DirectConversationItem(
      peer: DirectMessagePeer.decode(_field(record, 'Peer')),
      lastMessage: lastMessage,
      unreadCount: asCount(_field(record, 'UnreadCount')),
      peerLastReadMessageId: asInt(_field(record, 'PeerLastReadMessageId'), 0),
      isBlockedByMe: asBool(_field(record, 'IsBlockedByMe'), false),
      canSend: asBool(_field(record, 'CanSend'), false),
    );
  }
}

class DirectConversationsPage {
  const DirectConversationsPage({
    required this.items,
    required this.hasMore,
    required this.nextBeforeMessageId,
  });

  final List<DirectConversationItem> items;
  final bool hasMore;
  final int nextBeforeMessageId;

  static DirectConversationsPage decode(Object? value) {
    final record = asRecord(value, '私信会话列表响应');
    final items = <DirectConversationItem>[];
    for (final entry in asArray(_field(record, 'Items'), '私信会话列表')) {
      final item = DirectConversationItem.decodeOrNull(entry);
      if (item != null) items.add(item);
    }
    return DirectConversationsPage(
      items: items,
      hasMore: asBool(_field(record, 'HasMore'), false),
      nextBeforeMessageId: asInt(_field(record, 'NextBeforeMessageId'), 0),
    );
  }
}

/// 消息按时间正序返回。会话不存在时也返回合法的对方资料和空列表。
class DirectMessagesPage {
  const DirectMessagesPage({
    required this.peer,
    required this.items,
    required this.hasMore,
    required this.nextBeforeMessageId,
    required this.myLastReadMessageId,
    required this.peerLastReadMessageId,
    required this.unreadCount,
    required this.isBlockedByMe,
    required this.canSend,
  });

  final DirectMessagePeer peer;
  final List<DirectMessageItem> items;
  final bool hasMore;
  final int nextBeforeMessageId;
  final int myLastReadMessageId;
  final int peerLastReadMessageId;
  final int unreadCount;
  final bool isBlockedByMe;
  final bool canSend;

  static DirectMessagesPage decode(Object? value) {
    final record = asRecord(value, '私信记录响应');
    return DirectMessagesPage(
      peer: DirectMessagePeer.decode(_field(record, 'Peer')),
      items: asArray(
        _field(record, 'Items'),
        '私信记录',
      ).map(DirectMessageItem.decode).toList(growable: false),
      hasMore: asBool(_field(record, 'HasMore'), false),
      nextBeforeMessageId: asInt(_field(record, 'NextBeforeMessageId'), 0),
      myLastReadMessageId: asInt(_field(record, 'MyLastReadMessageId'), 0),
      peerLastReadMessageId: asInt(_field(record, 'PeerLastReadMessageId'), 0),
      unreadCount: asCount(_field(record, 'UnreadCount')),
      isBlockedByMe: asBool(_field(record, 'IsBlockedByMe'), false),
      canSend: asBool(_field(record, 'CanSend'), false),
    );
  }
}

class DirectMessageSendResult {
  const DirectMessageSendResult({
    required this.message,
    required this.peerLastReadMessageId,
  });

  final DirectMessageItem message;
  final int peerLastReadMessageId;

  static DirectMessageSendResult decode(Object? value) {
    final record = asRecord(value, '私信发送响应');
    return DirectMessageSendResult(
      message: DirectMessageItem.decode(_field(record, 'Message')),
      peerLastReadMessageId: asInt(_field(record, 'PeerLastReadMessageId'), 0),
    );
  }
}

class DirectMessageReadResult {
  const DirectMessageReadResult({
    required this.myLastReadMessageId,
    required this.unreadCount,
  });

  final int myLastReadMessageId;
  final int unreadCount;

  static DirectMessageReadResult decode(Object? value) {
    final record = asRecord(value, '私信已读响应');
    return DirectMessageReadResult(
      myLastReadMessageId: asInt(_field(record, 'MyLastReadMessageId'), 0),
      unreadCount: asCount(_field(record, 'UnreadCount')),
    );
  }
}

class DirectMessageBlockResult {
  const DirectMessageBlockResult({
    required this.isBlockedByMe,
    required this.canSend,
  });

  final bool isBlockedByMe;
  final bool canSend;

  static DirectMessageBlockResult decode(Object? value) {
    final record = asRecord(value, '私信拉黑响应');
    return DirectMessageBlockResult(
      isBlockedByMe: asBool(_field(record, 'IsBlockedByMe'), false),
      canSend: asBool(_field(record, 'CanSend'), false),
    );
  }
}

/// 服务端推送的私信事件。[peerId] 一律是「相对当前连接的对方」。
sealed class DirectMessageEvent {
  const DirectMessageEvent(this.peerId);

  final int peerId;
}

class DirectMessageReceived extends DirectMessageEvent {
  const DirectMessageReceived(super.peerId, this.message);

  final DirectMessageItem message;

  static DirectMessageReceived? decode(Object? value) {
    final record = asRecordOrNull(value);
    if (record == null) return null;
    final message = DirectMessageItem.decodeOrNull(_field(record, 'Message'));
    if (message == null) return null;
    return DirectMessageReceived(asInt(_field(record, 'PeerId'), 0), message);
  }
}

/// 阅读者本人与对方收到同一份，靠 [readerId] 区分。
class DirectMessageReadReceipt extends DirectMessageEvent {
  const DirectMessageReadReceipt(
    super.peerId,
    this.readerId,
    this.throughMessageId,
  );

  final int readerId;
  final int throughMessageId;

  static DirectMessageReadReceipt? decode(Object? value) {
    final record = asRecordOrNull(value);
    if (record == null) return null;
    return DirectMessageReadReceipt(
      asInt(_field(record, 'PeerId'), 0),
      asInt(_field(record, 'ReaderId'), 0),
      asInt(_field(record, 'ThroughMessageId'), 0),
    );
  }
}

class DirectMessageBlockChanged extends DirectMessageEvent {
  const DirectMessageBlockChanged(
    super.peerId,
    this.isBlockedByMe,
    this.canSend,
  );

  final bool isBlockedByMe;
  final bool canSend;

  static DirectMessageBlockChanged? decode(Object? value) {
    final record = asRecordOrNull(value);
    if (record == null) return null;
    return DirectMessageBlockChanged(
      asInt(_field(record, 'PeerId'), 0),
      asBool(_field(record, 'IsBlockedByMe'), false),
      asBool(_field(record, 'CanSend'), false),
    );
  }
}
