import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/discover/book_list_screen.dart';
import 'package:lightnovel/features/discover/novel_series_books_screen.dart';
import 'package:lightnovel/features/discover/widgets/novel_series_tile.dart';

/// 全部小说列表的单本 / 系列视图切换。

Map<String, dynamic> _book(int id, String title) => <String, dynamic>{
  'Id': id,
  'Type': 'Novel',
  'Title': title,
  'Cover': 'https://img.test/$id.jpg',
  'UserName': '上传者',
  'LastUpdatedAt': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _listPage(List<Map<String, dynamic>> data) =>
    <String, dynamic>{'Page': 1, 'TotalPages': 1, 'Data': data};

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
      case 'GetBookList':
        return decode(_listPage(<Map<String, dynamic>>[_book(1, '单本甲')]));
      case 'GetSeriesList':
        return decode(
          _listPage(<Map<String, dynamic>>[
            <String, dynamic>{
              'Name': '系列甲',
              'Count': 3,
              'Cover': null,
              'LastUpdatedAt': '2026-01-01T00:00:00Z',
            },
          ]),
        );
      case 'GetBooksBySeries':
        return decode(_listPage(<Map<String, dynamic>>[_book(2, '系列甲 第一卷')]));
    }
    throw UnimplementedError(methodName);
  }
}

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

Future<_FakeApi> _open(WidgetTester tester) async {
  final api = _FakeApi();
  final router = GoRouter(
    initialLocation: '/books',
    routes: <RouteBase>[
      GoRoute(path: '/books', builder: (_, _) => const BookListScreen()),
      GoRoute(
        path: '/books/series',
        builder: (_, state) => NovelSeriesBooksScreen(
          seriesName: state.uri.queryParameters['name'] ?? '',
          initialOrder:
              bookListOrderFromWire(state.uri.queryParameters['order']) ??
              BookListOrder.latest,
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api),
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(_MemoryStore(), const AppSettings()),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Future<void> _switchTo(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('展示方式'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认单本模式，走 GetBookList', (tester) async {
    final api = await _open(tester);

    expect(find.text('单本甲'), findsOneWidget);
    expect(find.byType(NovelSeriesTile), findsNothing);
    expect(api.calls.first.$1, 'GetBookList');
  });

  testWidgets('切到系列模式后按系列分组展示', (tester) async {
    final api = await _open(tester);

    await _switchTo(tester, '系列');

    expect(find.byType(NovelSeriesTile), findsOneWidget);
    expect(find.text('系列甲'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('单本甲'), findsNothing);

    final request = api.calls
        .firstWhere((call) => call.$1 == 'GetSeriesList')
        .$2;
    expect(request['Type'], 'Novel');
    expect(request['Order'], 'latest');
  });

  testWidgets('系列模式下换排序会重新按新排序取系列', (tester) async {
    final api = await _open(tester);

    await _switchTo(tester, '系列');
    await tester.tap(find.text('最多阅读'));
    await tester.pumpAndSettle();

    final orders = api.calls
        .where((call) => call.$1 == 'GetSeriesList')
        .map((call) => call.$2['Order'])
        .toList();
    expect(orders, <String>['latest', 'view']);
  });

  testWidgets('点系列卡片进入系列内书籍', (tester) async {
    final api = await _open(tester);

    await _switchTo(tester, '系列');
    await tester.tap(find.byType(NovelSeriesTile));
    await tester.pumpAndSettle();

    expect(find.text('系列甲 第一卷'), findsOneWidget);
    final request = api.calls
        .firstWhere((call) => call.$1 == 'GetBooksBySeries')
        .$2;
    expect(request['SeriesName'], '系列甲');
    expect(request['Type'], 'Novel');
    expect(request['Order'], 'latest');
  });

  testWidgets('切回单本模式回到平铺列表', (tester) async {
    await _open(tester);

    await _switchTo(tester, '系列');
    await _switchTo(tester, '单本');

    expect(find.text('单本甲'), findsOneWidget);
    expect(find.byType(NovelSeriesTile), findsNothing);
  });
}
