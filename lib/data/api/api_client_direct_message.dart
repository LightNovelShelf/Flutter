import '../../core/network/request_scheduler.dart';
import 'api_client.dart';
import 'models.dart';

/// 一对一私信。发送者身份由服务端从令牌取，请求里只带对方 ID。
extension ApiClientDirectMessage on ApiClient {
  /// 会话列表，按最后一条消息倒序；[beforeMessageId] 为 0 取最新一页。
  Future<DirectConversationsPage> getDirectConversations({
    int beforeMessageId = 0,
    int size = 20,
    CancelToken? cancelToken,
  }) => invoke(
    'GetDirectConversations',
    <String, Object?>{'BeforeMessageId': beforeMessageId, 'Size': size},
    DirectConversationsPage.decode,
    cancelToken: cancelToken,
  );

  /// 与某人的历史消息，返回的 `items` 按时间正序。
  Future<DirectMessagesPage> getDirectMessages({
    required int peerUserId,
    int beforeMessageId = 0,
    int size = 30,
    CancelToken? cancelToken,
  }) => invoke(
    'GetDirectMessages',
    <String, Object?>{
      'PeerUserId': peerUserId,
      'BeforeMessageId': beforeMessageId,
      'Size': size,
    },
    DirectMessagesPage.decode,
    cancelToken: cancelToken,
  );

  /// [clientMessageId] 是幂等键，重试必须复用同一个，否则会发出两条消息。
  Future<DirectMessageSendResult> sendDirectMessage({
    required int recipientUserId,
    required String clientMessageId,
    required String content,
  }) => invoke('SendDirectMessage', <String, Object?>{
    'RecipientUserId': recipientUserId,
    'ClientMessageId': clientMessageId,
    'Content': content,
  }, DirectMessageSendResult.decode);

  Future<DirectMessageReadResult> markDirectMessagesRead({
    required int peerUserId,
    required int throughMessageId,
  }) => invoke('MarkDirectMessagesRead', <String, Object?>{
    'PeerUserId': peerUserId,
    'ThroughMessageId': throughMessageId,
  }, DirectMessageReadResult.decode);

  Future<DirectMessageBlockResult> setDirectMessageBlock({
    required int userId,
    required bool isBlocked,
  }) => invoke('SetDirectMessageBlock', <String, Object?>{
    'UserId': userId,
    'IsBlocked': isBlocked,
  }, DirectMessageBlockResult.decode);
}
