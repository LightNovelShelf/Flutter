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
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/app_runtime.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/session/auth_controller.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/book/comments_screen.dart';
import 'package:lightnovel/features/community/community_notifications_screen.dart';

/// 系列通知没有实体 id，只能按 `series_title` 跳到系列评论区。
const String _seriesTitle = '某漫画系列';

Map<String, Object?> _notification({
  required String objectType,
  int objectId = 0,
  String? seriesTitle,
  String objectTitle = '',
  int? replyId,
}) => <String, Object?>{
  'Id': 1,
  'Type': 'Comment',
  'ObjectType': objectType,
  'ObjectId': objectId,
  'IsRead': false,
  'CreatedAt': '2026-01-01T00:00:00Z',
  'Extra': <String, Object?>{
    'object_id': objectId,
    'object_title': objectTitle,
    'series_title': seriesTitle,
    'preview': '正文',
    'reply_id': replyId,
  },
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
      case 'GetComments':
        return decode(<String, Object?>{
          'Page': 1,
          'TotalPages': 1,
          'Data': <Object?>[
            <String, Object?>{'Id': 9, 'Reply': null},
          ],
          'Users': <String, Object?>{
            '3': <String, Object?>{'Id': 3, 'UserName': '读者', 'Avatar': ''},
          },
          'Commentaries': <String, Object?>{
            '9': <String, Object?>{
              'UserId': 3,
              'Content': '系列评论内容',
              'CreatedAt': '2026-01-01T00:00:00Z',
              'CanEdit': false,
            },
          },
        });
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

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  test('系列通知按系列标题跳评论区', () {
    final route = notificationRoute(
      AppNotificationItem.decode(
        _notification(objectType: 'Series', seriesTitle: _seriesTitle),
      ),
    );

    expect(route, isNotNull);
    final uri = Uri.parse(route!);
    expect(uri.path, '/books/series/comments');
    expect(uri.queryParameters['name'], _seriesTitle);
  });

  test('系列通知缺系列标题时无处可跳', () {
    expect(
      notificationRoute(
        AppNotificationItem.decode(_notification(objectType: 'Series')),
      ),
      isNull,
    );
  });

  test('其余通知类型的跳转不变', () {
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(objectType: 'Book', objectId: 42, objectTitle: '某本小说'),
        ),
      ),
      '/book/42/comments?title=%E6%9F%90%E6%9C%AC%E5%B0%8F%E8%AF%B4',
    );
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(objectType: 'Announcement', objectId: 7),
        ),
      ),
      '/announcement/7',
    );
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(
            objectType: 'CommunityThread',
            objectId: 5,
            replyId: 11,
          ),
        ),
      ),
      '/community/thread/5?replyId=11',
    );
  });

  testWidgets('系列通知的目标路由拉取该系列的评论', (tester) async {
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

    final route = notificationRoute(
      AppNotificationItem.decode(
        _notification(objectType: 'Series', seriesTitle: _seriesTitle),
      ),
    );
    router.push(route!);
    await tester.pumpAndSettle();

    expect(find.byType(CommentsScreen), findsOneWidget);
    expect(find.text('系列评论内容'), findsOneWidget);
    final request = api.calls.firstWhere((call) => call.$1 == 'GetComments').$2;
    expect(request['Type'], 'Series');
    expect(request['SeriesTitle'], _seriesTitle);
    expect(request['Id'], 0);
  });
}
