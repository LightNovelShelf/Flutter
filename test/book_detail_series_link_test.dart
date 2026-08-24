import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/retry_policy.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/book/book_detail_screen.dart';
import 'package:lightnovel/features/book/book_providers.dart';
import 'package:lightnovel/features/discover/novel_series_books_screen.dart';

/// 详情页标题进入系列列表，系列键与服务端 `SeriesTitle` 一致（中文名优先）。
const int _bookId = 42;
const String _bookTitle = '某本小说 第一卷';

/// 服务端对无权访问的书籍返回业务错误，`ApiClient` 抛成 [ApiError]。
const String _forbiddenMessage = '您没有权限访问这本书';

Map<String, dynamic> _detailResponse() => <String, dynamic>{
  'Book': <String, dynamic>{
    'Id': _bookId,
    'Type': 'Novel',
    'Title': _bookTitle,
    'Cover': 'https://img.test/$_bookId.jpg',
    'Author': '作者',
    'Introduction': '简介',
    'LastUpdatedAt': '2026-01-01T00:00:00Z',
    'CreatedAt': '2025-01-01T00:00:00Z',
    'Favorite': 1,
    'Views': 2,
    'CanEdit': false,
    'Chapter': <Map<String, dynamic>>[
      <String, dynamic>{'Id': 1, 'Title': '第一章'},
    ],
    'Extra': <String, dynamic>{
      'classification': <String, dynamic>{
        'series_name': '原名シリーズ',
        'series_name_cn': '中文系列',
        'tags': <String>[],
      },
    },
  },
  'ReadPosition': null,
};

class _FakeApi extends ApiClient {
  _FakeApi({this.forbidBookInfo = false})
    : super(
        signalR: SignalRConnection(
          endpoint: 'http://localhost/hub',
          accessTokenFactory: () async => null,
        ),
        scheduler: RateLimitRequestScheduler(),
        headers: () async => const <String, String>{},
      );

  /// 详情接口是否返回无权访问。
  final bool forbidBookInfo;

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
      case 'GetBookInfo':
        if (forbidBookInfo) {
          throw const ApiError(_forbiddenMessage, ApiErrorCategory.server);
        }
        return decode(_detailResponse());
      case 'GetBooksBySeries':
        return decode(<String, dynamic>{
          'Page': 1,
          'TotalPages': 1,
          'Data': <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 7,
              'Type': 'Novel',
              'Title': '同系列的另一本',
              'Cover': 'https://img.test/7.jpg',
              'UserName': '上传者',
              'LastUpdatedAt': '2026-01-01T00:00:00Z',
            },
          ],
        });
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

Future<({_FakeApi api, GoRouter router})> _open(
  WidgetTester tester, {
  String initialLocation = '/book/$_bookId',
  bool forbidBookInfo = false,
}) async {
  final api = _FakeApi(forbidBookInfo: forbidBookInfo);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/book/:id',
        builder: (_, state) => BookDetailScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          type: BookType.novel,
          seriesTitle: state.uri.queryParameters['seriesTitle'],
          fromSeries: state.uri.queryParameters['fromSeries'],
        ),
      ),
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
      // 与 main 保持一致，否则测到的是 Riverpod 默认的十次退避重试。
      retry: apiRetry,
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api),
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(_MemoryStore(), const AppSettings()),
        ),
        bookInShelfProvider.overrideWith((ref, bookId) async => false),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, router: router);
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('点小说标题进入所属系列，系列键取中文名', (tester) async {
    final opened = await _open(tester);

    await tester.tap(find.text(_bookTitle));
    await tester.pumpAndSettle();

    expect(find.text('同系列的另一本'), findsOneWidget);
    final request = opened.api.calls
        .firstWhere((call) => call.$1 == 'GetBooksBySeries')
        .$2;
    expect(request['SeriesName'], '中文系列');
    expect(request['Type'], 'Novel');
  });

  testWidgets('列表页带来的系列键优先于分类器字段', (tester) async {
    final opened = await _open(
      tester,
      initialLocation:
          '/book/$_bookId?seriesTitle=%E5%88%97%E8%A1%A8%E7%BB%99%E7%9A%84%E7%B3%BB%E5%88%97',
    );

    await tester.tap(find.text(_bookTitle));
    await tester.pumpAndSettle();

    final request = opened.api.calls
        .firstWhere((call) => call.$1 == 'GetBooksBySeries')
        .$2;
    expect(request['SeriesName'], '列表给的系列');
  });

  testWidgets('从系列页点进详情再点标题，原路返回而不是叠一层', (tester) async {
    final opened = await _open(
      tester,
      initialLocation: '/books/series?name=%E4%B8%AD%E6%96%87%E7%B3%BB%E5%88%97&order=latest',
    );

    await tester.tap(find.text('同系列的另一本'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);

    await tester.tap(find.text(_bookTitle));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailScreen), findsNothing);
    expect(find.byType(NovelSeriesBooksScreen), findsOneWidget);
    // 没有重复压入同名系列页。
    expect(opened.router.canPop(), isFalse);
  });

  /// 详情页正常态的返回按钮挂在 `_body` 的 `SliverAppBar` 上，取不到数据时那条
  /// AppBar 不渲染。桌面端没有手势返回，错误页上的返回按钮是唯一的退出入口。
  testWidgets('无权访问的书籍在错误页上留返回入口，桌面端能退回上一页', (tester) async {
    await _open(
      tester,
      initialLocation: '/books/series?name=%E4%B8%AD%E6%96%87%E7%B3%BB%E5%88%97&order=latest',
      forbidBookInfo: true,
    );

    await tester.tap(find.text('同系列的另一本'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);

    final back = find.widgetWithText(TextButton, '返回');
    expect(back, findsOneWidget);

    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailScreen), findsNothing);
    expect(find.byType(NovelSeriesBooksScreen), findsOneWidget);
  });

  /// 业务错误重试多少次都是同一个结果，[apiRetry] 让它一次都不退避，
  /// 页面立刻给出原因而不是先在骨架屏上干等。
  testWidgets('无权访问不重试，详情页直接给出服务端文案', (tester) async {
    final opened = await _open(
      tester,
      initialLocation: '/books/series?name=%E4%B8%AD%E6%96%87%E7%B3%BB%E5%88%97&order=latest',
      forbidBookInfo: true,
    );

    await tester.tap(find.text('同系列的另一本'));
    await tester.pumpAndSettle();

    expect(find.text('无法加载这本书'), findsOneWidget);
    expect(find.text(_forbiddenMessage), findsOneWidget);
    expect(
      opened.api.calls.where((call) => call.$1 == 'GetBookInfo').length,
      1,
    );
  });
}
