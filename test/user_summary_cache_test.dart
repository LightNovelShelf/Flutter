import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/repositories/user_summary.dart';

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

  final List<int> requested = <int>[];

  /// 非空时挡住响应，用来构造「同一个人的请求还在路上」。
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    expect(methodName, 'GetUserSummary');
    final userId = (params! as Map<String, Object?>)['UserId']! as int;
    requested.add(userId);
    await gate?.future;
    if (fail) throw const ApiError('用户不存在', ApiErrorCategory.server);
    return decode(<String, Object?>{
      'Id': userId,
      'UserName': '用户$userId',
      'Avatar': '',
      'Role': '注册会员',
      'Level': 1,
      'RegisterAt': '2021-12-05T22:45:17Z',
      'BookCount': 0,
      'CommunityThreadCount': 0,
      'CommunityReplyCount': 0,
      'CommentCount': 0,
    });
  }
}

void main() {
  test('缓存期内重复打开同一个人不再请求', () async {
    final api = _FakeApi();
    final cache = UserSummaryCache(api);

    expect((await cache.load(7)).userName, '用户7');
    expect((await cache.load(7)).userName, '用户7');

    expect(api.requested, <int>[7]);
  });

  test('过期后重新请求', () async {
    final api = _FakeApi();
    final cache = UserSummaryCache(api, ttl: const Duration(milliseconds: 20));

    await cache.load(7);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await cache.load(7);

    expect(api.requested, <int>[7, 7]);
  });

  test('同一个人的并发请求合并成一次', () async {
    final api = _FakeApi()..gate = Completer<void>();
    final cache = UserSummaryCache(api);

    final first = cache.load(7);
    final second = cache.load(7);
    api.gate!.complete();
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(api.requested, <int>[7]);
  });

  test('超出容量淘汰最久没用到的人', () async {
    final api = _FakeApi();
    final cache = UserSummaryCache(api, capacity: 2);

    await cache.load(1);
    await cache.load(2);
    // 读一次 1，最久没用到的变成 2
    await cache.load(1);
    await cache.load(3);

    expect(cache.read(1), isNotNull);
    expect(cache.read(2), isNull);
    expect(cache.read(3), isNotNull);
    expect(api.requested, <int>[1, 2, 3]);
  });

  test('失败不写缓存，重试重新请求', () async {
    final api = _FakeApi()..fail = true;
    final cache = UserSummaryCache(api);

    await expectLater(cache.load(7), throwsA(isA<ApiError>()));
    api.fail = false;
    expect((await cache.load(7)).userName, '用户7');

    expect(api.requested, <int>[7, 7]);
  });
}
