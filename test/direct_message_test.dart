import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lightnovel/app/home_shell.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/repositories/direct_message_realtime.dart';
import 'package:lightnovel/data/repositories/profile_repository.dart';
import 'package:lightnovel/data/repositories/unread_counts.dart';
import 'package:lightnovel/features/message/direct_message_providers.dart';

const int _peerId = 2;

/// 服务端推送走 SignalR 的 JSON 协议，字段是 camelCase；Hub 响应走 gzip 通道是 PascalCase。
Map<String, Object?> _message(int id, int senderId, String clientMessageId) =>
    <String, Object?>{
      'id': id,
      'clientMessageId': clientMessageId,
      'senderId': senderId,
      'content': '在吗',
      'createdAt': '2026-09-06T10:00:00Z',
    };

Map<String, Object?> _push(int id, int senderId, String clientMessageId) =>
    <String, Object?>{
      'peerId': _peerId,
      'message': _message(id, senderId, clientMessageId),
    };

Map<String, Object?> _conversation(int peerId, int messageId) =>
    <String, Object?>{
      'Peer': <String, Object?>{
        'Id': peerId,
        'UserName': '用户$peerId',
        'Avatar': '',
        'IsDeleted': false,
      },
      'LastMessage': _message(messageId, peerId, 'message-$messageId'),
      'UnreadCount': 0,
      'PeerLastReadMessageId': 0,
      'IsBlockedByMe': false,
      'CanSend': true,
    };

class _FakeApi extends ApiClient {
  _FakeApi()
    : super(
        signalR: SignalRConnection(
          endpoint: 'http://localhost/hub',
          accessTokenFactory: () async => null,
        ),
        scheduler: RateLimitRequestScheduler(),
        headers: () async => const <String, String>{},
      );

  final List<(String, Object?)> calls = <(String, Object?)>[];

  /// 挡住发送响应，用来构造「推送先于响应到达」。
  Completer<void>? sendGate;

  Completer<void>? messageLoadGate;
  final Completer<void> messageLoadStarted = Completer<void>();
  bool messagePageHasMore = false;
  int messagePageNextBeforeMessageId = 0;
  List<Object?> messagePageItems = const <Object?>[];

  Completer<void>? markGate;
  final Completer<void> markStarted = Completer<void>();

  Completer<void>? conversationLoadMoreGate;
  final Completer<void> conversationLoadMoreStarted = Completer<void>();
  final Completer<void> conversationReconciled = Completer<void>();
  int conversationFirstPageCalls = 0;

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    calls.add((methodName, params));
    final request = params as Map<String, Object?>;
    switch (methodName) {
      case 'GetDirectConversations':
        final beforeMessageId = request['BeforeMessageId']! as int;
        if (beforeMessageId > 0) {
          if (!conversationLoadMoreStarted.isCompleted) {
            conversationLoadMoreStarted.complete();
          }
          await conversationLoadMoreGate?.future;
          return decode(<String, Object?>{
            'Items': <Object?>[_conversation(3, 90)],
            'HasMore': false,
            'NextBeforeMessageId': 90,
          });
        }
        conversationFirstPageCalls += 1;
        if (conversationFirstPageCalls > 1 &&
            !conversationReconciled.isCompleted) {
          conversationReconciled.complete();
        }
        final latestMessageId = conversationFirstPageCalls == 1 ? 100 : 101;
        return decode(<String, Object?>{
          'Items': <Object?>[_conversation(_peerId, latestMessageId)],
          'HasMore': true,
          'NextBeforeMessageId': latestMessageId,
        });
      case 'GetDirectMessages':
        if (!messageLoadStarted.isCompleted) messageLoadStarted.complete();
        await messageLoadGate?.future;
        return decode(<String, Object?>{
          'Peer': <String, Object?>{
            'Id': _peerId,
            'UserName': '对方',
            'Avatar': '',
            'IsDeleted': false,
          },
          'Items': messagePageItems,
          'HasMore': messagePageHasMore,
          'NextBeforeMessageId': messagePageNextBeforeMessageId,
          'MyLastReadMessageId': 0,
          'PeerLastReadMessageId': 0,
          'UnreadCount': 0,
          'IsBlockedByMe': false,
          'CanSend': true,
        });
      case 'SendDirectMessage':
        await sendGate?.future;
        return decode(<String, Object?>{
          'Message': <String, Object?>{
            'Id': 10,
            'ClientMessageId': request['ClientMessageId'],
            'SenderId': 1,
            'Content': request['Content'],
            'CreatedAt': '2026-09-06T10:00:00Z',
          },
          'PeerLastReadMessageId': 0,
        });
      case 'MarkDirectMessagesRead':
        if (!markStarted.isCompleted) markStarted.complete();
        await markGate?.future;
        return decode(<String, Object?>{
          'MyLastReadMessageId': request['ThroughMessageId'],
          'UnreadCount': 0,
        });
    }
    throw UnimplementedError(methodName);
  }
}

class _StubProfile extends ProfileController {
  _StubProfile(this.notifications, this.messages);

  final int notifications;
  final int messages;
  int quietRefreshes = 0;

  @override
  Future<UserProfile?> build() async => UserProfile.decode(<String, Object?>{
    'Id': 1,
    'UserName': '我',
    'Avatar': '',
    'Email': '',
    'InviteCode': '',
    'Role': <String, Object?>{'Name': ''},
    'UnreadNotificationCount': notifications,
    'UnreadDirectMessageCount': messages,
    'RegisterAt': null,
    'Growth': const <String, Object?>{},
  });

  @override
  Future<void> refreshQuietly() async {
    quietRefreshes += 1;
  }
}

({
  ProviderContainer container,
  _FakeApi api,
  StreamController<DirectMessageEvent> events,
  _StubProfile profile,
})
_setUp({int notifications = 0, int messages = 0}) {
  final api = _FakeApi();
  final events = StreamController<DirectMessageEvent>.broadcast();
  final profile = _StubProfile(notifications, messages);
  final container = ProviderContainer(
    overrides: <Override>[
      apiClientProvider.overrideWithValue(api),
      directMessageEventProvider.overrideWith((ref) => events.stream),
      profileProvider.overrideWith(() => profile),
    ],
  );
  addTearDown(events.close);
  addTearDown(container.dispose);
  return (container: container, api: api, events: events, profile: profile);
}

void main() {
  test('解码 JSON 协议推送的 camelCase 载荷', () {
    final received = decodeDirectMessageInvocation(
      ServerInvocation('OnDirectMessage', <Object?>[_push(7, _peerId, 'abc')]),
    );
    expect(received, isA<DirectMessageReceived>());
    final message = (received! as DirectMessageReceived).message;
    expect(received.peerId, _peerId);
    expect(message.id, 7);
    expect(message.senderId, _peerId);
    expect(message.clientMessageId, 'abc');
    expect(message.content, '在吗');

    final read = decodeDirectMessageInvocation(
      ServerInvocation('OnDirectMessageRead', <Object?>[
        <String, Object?>{
          'peerId': _peerId,
          'readerId': _peerId,
          'throughMessageId': 9,
          'readAt': '2026-09-06T10:00:00Z',
        },
      ]),
    );
    expect(read, isA<DirectMessageReadReceipt>());
    expect((read! as DirectMessageReadReceipt).throughMessageId, 9);

    final blocked = decodeDirectMessageInvocation(
      ServerInvocation('OnDirectMessageBlockChanged', <Object?>[
        <String, Object?>{
          'peerId': _peerId,
          'isBlockedByMe': true,
          'canSend': false,
        },
      ]),
    );
    expect(blocked, isA<DirectMessageBlockChanged>());
    expect((blocked! as DirectMessageBlockChanged).isBlockedByMe, isTrue);

    expect(
      decodeDirectMessageInvocation(
        ServerInvocation('OnMessage', const <Object?>[]),
      ),
      isNull,
    );
  });

  test('推送早于发送响应到达时不重复渲染自己发的消息', () async {
    final env = _setUp();
    // autoDispose 的 provider 需要有订阅者才活着。
    env.container.listen(directChatProvider(_peerId), (_, _) {});
    final controller = env.container.read(directChatProvider(_peerId).notifier);
    await Future<void>.delayed(Duration.zero);

    env.api.sendGate = Completer<void>();
    controller.send('在吗');
    final clientMessageId = env.container
        .read(directChatProvider(_peerId))
        .pending
        .single
        .clientMessageId;

    env.events.add(
      DirectMessageReceived.decode(_push(10, 1, clientMessageId))!,
    );
    await Future<void>.delayed(Duration.zero);
    expect(env.container.read(directChatProvider(_peerId)).pending, isEmpty);

    env.api.sendGate!.complete();
    await Future<void>.delayed(Duration.zero);

    final state = env.container.read(directChatProvider(_peerId));
    expect(state.messages.map((item) => item.id), <int>[10]);
    expect(state.pending, isEmpty);
  });

  test('会话开着时收到对方消息立即提交已读', () async {
    final env = _setUp();
    env.container.listen(directChatProvider(_peerId), (_, _) {});
    env.container.read(directChatProvider(_peerId).notifier);
    await Future<void>.delayed(Duration.zero);

    env.events.add(DirectMessageReceived.decode(_push(12, _peerId, 'x'))!);
    await Future<void>.delayed(Duration.zero);

    final marked = env.api.calls
        .where((call) => call.$1 == 'MarkDirectMessagesRead')
        .single;
    expect((marked.$2! as Map<String, Object?>)['ThroughMessageId'], 12);
    expect(
      env.container.read(directChatProvider(_peerId)).myLastReadMessageId,
      12,
    );
  });

  test('已读提交期间的新消息会补交最新游标', () async {
    final env = _setUp();
    env.api.markGate = Completer<void>();
    env.container.listen(directChatProvider(_peerId), (_, _) {});
    env.container.read(directChatProvider(_peerId).notifier);
    await env.api.messageLoadStarted.future;
    await Future<void>.delayed(Duration.zero);

    env.events.add(DirectMessageReceived.decode(_push(12, _peerId, 'x'))!);
    await env.api.markStarted.future;
    env.events.add(DirectMessageReceived.decode(_push(13, _peerId, 'y'))!);
    await Future<void>.delayed(Duration.zero);
    env.api.markGate!.complete();
    await pumpEventQueue();

    final cursors = env.api.calls
        .where((call) => call.$1 == 'MarkDirectMessagesRead')
        .map(
          (call) =>
              (call.$2! as Map<String, Object?>)['ThroughMessageId']! as int,
        )
        .toList();
    expect(cursors, <int>[12, 13]);
    expect(
      env.container.read(directChatProvider(_peerId)).myLastReadMessageId,
      13,
    );
  });

  test('初次加载期间收到推送仍保留历史分页游标', () async {
    final env = _setUp();
    env.api.messageLoadGate = Completer<void>();
    env.api.messagePageHasMore = true;
    env.api.messagePageNextBeforeMessageId = 100;
    env.api.messagePageItems = <Object?>[_message(100, 1, 'history')];
    env.container.listen(directChatProvider(_peerId), (_, _) {});
    env.container.read(directChatProvider(_peerId).notifier);
    await env.api.messageLoadStarted.future;

    env.events.add(DirectMessageReceived.decode(_push(101, _peerId, 'new'))!);
    await Future<void>.delayed(Duration.zero);
    env.api.messageLoadGate!.complete();
    await pumpEventQueue();

    final state = env.container.read(directChatProvider(_peerId));
    expect(state.hasMore, isTrue);
    expect(state.nextBeforeMessageId, 100);
    expect(state.messages.map((item) => item.id), <int>[100, 101]);
  });

  test('推送对账打断分页后会释放加载状态', () async {
    final env = _setUp();
    env.api.conversationLoadMoreGate = Completer<void>();
    env.container.listen(directConversationListProvider, (_, _) {});
    await pumpEventQueue();
    final controller = env.container.read(
      directConversationListProvider.notifier,
    );

    controller.loadMore();
    await env.api.conversationLoadMoreStarted.future;
    env.events.add(DirectMessageReceived.decode(_push(101, _peerId, 'new'))!);
    await env.api.conversationReconciled.future;
    env.api.conversationLoadMoreGate!.complete();
    await pumpEventQueue();

    expect(
      env.container.read(directConversationListProvider).loadingMore,
      isFalse,
    );
  });

  test('社区未读角标聚合通知与私信', () async {
    final env = _setUp(notifications: 3, messages: 5);
    await env.container.read(profileProvider.future);

    expect(env.container.read(communityUnreadCountProvider), 8);
  });

  testWidgets('应用恢复前台会对账未读资料', (tester) async {
    final env = _setUp(notifications: 3, messages: 5);
    StatefulShellBranch branch(String path) => StatefulShellBranch(
      routes: <RouteBase>[
        GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    );

    final router = GoRouter(
      initialLocation: '/one',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => HomeShell(shell: shell),
          branches: <StatefulShellBranch>[
            branch('/one'),
            branch('/two'),
            branch('/three'),
            branch('/four'),
            branch('/five'),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(env.profile.quietRefreshes, 1);
  });
}
