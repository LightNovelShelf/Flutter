import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/signalr_connection.dart';
import '../api/models.dart';
import '../providers.dart';

/// 服务端推送的三个私信 target 合成一条流，页面与角标各自订阅。
final StreamProvider<DirectMessageEvent> directMessageEventProvider =
    StreamProvider<DirectMessageEvent>(
      (ref) => ref
          .watch(appRuntimeProvider)
          .signalR
          .serverMessages
          .map(decodeDirectMessageInvocation)
          .where((event) => event != null)
          .cast<DirectMessageEvent>(),
    );

/// 非私信推送与无法解析的载荷返回 null。
DirectMessageEvent? decodeDirectMessageInvocation(ServerInvocation invocation) {
  final payload = invocation.arguments.isEmpty
      ? null
      : invocation.arguments.first;
  return switch (invocation.target) {
    'OnDirectMessage' => DirectMessageReceived.decode(payload),
    'OnDirectMessageRead' => DirectMessageReadReceipt.decode(payload),
    'OnDirectMessageBlockChanged' => DirectMessageBlockChanged.decode(payload),
    _ => null,
  };
}
