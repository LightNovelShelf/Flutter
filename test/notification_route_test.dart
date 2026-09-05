import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/features/community/community_notifications_screen.dart';

Map<String, Object?> _notification({
  String kind = 'system.message',
  String tone = 'neutral',
  Map<String, Object?>? action,
  Map<String, Object?> data = const <String, Object?>{},
}) => <String, Object?>{
  'Id': 1,
  'Actor': null,
  'Kind': kind,
  'SchemaVersion': 1,
  'Title': '通知标题',
  'Body': '通知正文',
  'Tone': tone,
  'Action': action,
  'Data': data,
  'IsRead': false,
  'ReadAt': null,
  'CreatedAt': '2026-01-01T00:00:00Z',
};

Map<String, Object?> _action(String type, Map<String, Object?> data) =>
    <String, Object?>{'Type': type, 'Data': data};

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

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    if (methodName == 'GetNotifications') {
      return decode(<String, Object?>{
        'TotalPages': 1,
        'Page': 1,
        'Data': <Object?>[_notification(tone: 'warning')],
      });
    }
    throw UnimplementedError(methodName);
  }
}

void main() {
  test('解码通用系统通知和下划线业务数据', () {
    final item = AppNotificationItem.decode(
      _notification(
        kind: 'growth.balance.adjusted',
        tone: 'warning',
        data: const <String, Object?>{'exp_delta': -4, 'coin_delta': -3},
      ),
    );

    expect(item.kind, 'growth.balance.adjusted');
    expect(item.schemaVersion, 1);
    expect(item.title, '通知标题');
    expect(item.body, '通知正文');
    expect(item.tone, AppNotificationTone.warning);
    expect(item.actor, isNull);
    expect(item.action, isNull);
    expect(item.data['exp_delta'], -4);
    expect(item.data['coin_delta'], -3);
    expect(item.isRead, isFalse);
    expect(item.readAt, isNull);
  });

  test('未知语义色回落为中性', () {
    final item = AppNotificationItem.decode(_notification(tone: 'future-tone'));

    expect(item.tone, AppNotificationTone.neutral);
  });

  test('已注册通知动作生成安全站内路由', () {
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(
            action: _action('open_book', <String, Object?>{'book_id': 42}),
          ),
        ),
      ),
      '/book/42',
    );
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(
            action: _action('open_announcement', <String, Object?>{
              'announcement_id': 7,
            }),
          ),
        ),
      ),
      '/announcement/7',
    );

    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(
            action: _action('open_community_thread', <String, Object?>{
              'thread_id': 5,
              'reply_id': 11,
            }),
          ),
        ),
      ),
      '/community/thread/5?replyId=11',
    );
  });

  test('空动作、未知动作和错误参数都不跳转', () {
    expect(
      notificationRoute(AppNotificationItem.decode(_notification())),
      isNull,
    );
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(action: _action('unknown_action', <String, Object?>{})),
        ),
      ),
      isNull,
    );
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(
            action: _action('open_external_url', <String, Object?>{
              'url': 'https://example.com',
            }),
          ),
        ),
      ),
      isNull,
    );
    expect(
      notificationRoute(
        AppNotificationItem.decode(
          _notification(
            action: _action('open_book', <String, Object?>{'book_id': 0}),
          ),
        ),
      ),
      isNull,
    );
  });

  testWidgets('系统通知按通用标题正文和警告语义渲染', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[apiClientProvider.overrideWithValue(_FakeApi())],
        child: const MaterialApp(home: CommunityNotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('系统'), findsOneWidget);
    expect(find.text('通知标题'), findsOneWidget);
    expect(find.text('通知正文'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
}
