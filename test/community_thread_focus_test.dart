import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lightnovel/app/router.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/app_runtime.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/session/auth_controller.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/community/widgets/community_reply_row.dart';

/// 292 个主楼、目标子回复在第 61 条：旧实现要逐页翻找，这里必须一次请求就落位。
const int _threadId = 176;
const int _focusReplyId = 1722;
const int _focusRootId = 1343;
const int _rootTotal = 292;

Map<String, Object?> _reply({
  required int id,
  required String content,
  List<Map<String, Object?>> children = const <Map<String, Object?>>[],
  Map<String, Object?>? childPage,
}) => <String, Object?>{
  'Id': id,
  'AuthorName': '读者$id',
  'AuthorIsDeleted': false,
  'AuthorAvatar': '',
  'PublishedAt': '2026-08-24T01:31:24Z',
  'Content': content,
  'Likes': 0,
  'Liked': false,
  'CanDelete': false,
  'ChildReplies': children,
  'ChildPage':
      childPage ??
      <String, Object?>{
        'Page': 1,
        'Size': 3,
        'Total': children.length,
        'TotalPages': 1,
        'HasMore': false,
      },
};

/// 服务端锚点响应：目标主楼置顶，楼中楼快进到目标所在的第 12 页（每页 5 条）。
Map<String, Object?> _focusedThread() => <String, Object?>{
  'Id': _threadId,
  'BoardKey': 'chat',
  'BoardName': '闲聊',
  'Title': '2026年水贴',
  'Excerpt': '',
  'AuthorName': '楼主',
  'Replies': 545,
  'BodyHtml': '<p>正文</p>',
  'Liked': false,
  'Favorited': false,
  'CanEdit': false,
  'RepliesPage': <String, Object?>{
    'Page': 1,
    'Size': 5,
    'Total': _rootTotal,
    'TotalPages': 59,
    'HasMore': true,
  },
  'ReplyItems': <Map<String, Object?>>[
    _reply(
      id: _focusRootId,
      content: '被回复的主楼',
      children: <Map<String, Object?>>[
        _reply(id: 1616, content: '上下文一'),
        _reply(id: 1624, content: '上下文二'),
        _reply(id: 1659, content: '上下文三'),
        _reply(id: 1715, content: '上下文四'),
        _reply(id: _focusReplyId, content: '通知指向的这条'),
      ],
      childPage: <String, Object?>{
        'Page': 12,
        'Size': 5,
        'Total': 61,
        'TotalPages': 13,
        'HasMore': true,
      },
    ),
    _reply(id: 1724, content: '最新主楼'),
  ],
  'RelatedThreads': <Object?>[],
  'Focus': <String, Object?>{'ReplyId': _focusReplyId},
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

  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    final args = (params as Map<String, Object?>?) ?? const <String, Object?>{};
    calls.add((methodName, args));
    switch (methodName) {
      case 'GetCommunityThread':
        return decode(_focusedThread());
      case 'GetMyCommunityOverview':
        return decode(<String, Object?>{});
    }
    throw UnimplementedError(methodName);
  }
}

class _MemoryStore implements KeyValueStore, CredentialStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

Future<(_FakeApi, ProviderContainer)> _pumpRoute(
  WidgetTester tester,
  String route,
) async {
  final api = _FakeApi();
  final store = _MemoryStore();
  final signalR = SignalRConnection(
    endpoint: 'http://localhost/hub',
    accessTokenFactory: () async => null,
  );
  final runtime = AppRuntime(
    credentials: store,
    keyValueStore: store,
    settings: SettingsController(store, const AppSettings()),
    signalR: signalR,
    api: api,
    auth: AuthController(api: api, credentials: store, signalR: signalR),
    hasStoredSession: true,
  );
  final container = ProviderContainer(
    overrides: <Override>[
      appRuntimeProvider.overrideWithValue(runtime),
      authSnapshotProvider.overrideWithValue(
        const AuthenticationSnapshot(
          status: AuthenticationStatus.authenticated,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.push(route);
  await tester.pumpAndSettle();
  return (api, container);
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('通知深链只发一次带锚点的详情请求，不再逐页翻找', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (api, _) = await _pumpRoute(
      tester,
      '/community/thread/$_threadId?replyId=$_focusReplyId',
    );

    final threadCalls = api.calls
        .where((call) => call.$1 == 'GetCommunityThread')
        .toList();
    expect(threadCalls, hasLength(1));
    expect(threadCalls.single.$2['FocusReplyId'], _focusReplyId);
    expect(threadCalls.single.$2['ReplyPage'], 1);
    expect(
      api.calls.where((call) => call.$1 == 'GetCommunityReplyChildren'),
      isEmpty,
    );

    expect(find.text('被回复的主楼'), findsOneWidget);
    expect(find.text('通知指向的这条'), findsOneWidget);
    final target = tester.widget<CommunityReplyRow>(
      find.ancestor(
        of: find.text('通知指向的这条'),
        matching: find.byType(CommunityReplyRow),
      ),
    );
    expect(target.highlighted, isTrue);
  });

  testWidgets('普通进入不带锚点', (tester) async {
    final (api, _) = await _pumpRoute(tester, '/community/thread/$_threadId');

    final threadCalls = api.calls
        .where((call) => call.$1 == 'GetCommunityThread')
        .toList();
    expect(threadCalls, hasLength(1));
    expect(threadCalls.single.$2['FocusReplyId'], 0);
  });
}
