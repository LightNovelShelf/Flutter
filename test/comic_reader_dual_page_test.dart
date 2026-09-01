import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/repositories/read_position_cache.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/reader/comic_reader_screen.dart';
import 'package:lightnovel/features/reader/widgets/reader_status_pills.dart';
import 'package:lightnovel/shared/widgets/image_preview.dart';
import 'package:photo_view/photo_view_gallery.dart';

const int _bookId = 9;
const int _chapterId = 90;

/// 每页的像素尺寸；第 4 页是横跨两页的宽图。
const List<String> _pageSizes = <String>[
  '1000x1500',
  '1000x1500',
  '1000x1500',
  '1600x1000',
  '1000x1500',
  '1000x1500',
];

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
    final args = (params ?? const <String, Object?>{}) as Map<String, Object?>;
    switch (methodName) {
      case 'GetComicInfo':
        return decode(<String, Object?>{
          'Book': <String, Object?>{
            'Id': _bookId,
            'Cover': 'https://img.example/cover.webp',
            'Title': '测试漫画',
            'Author': '作者',
            'Views': 0,
            'Introduction': '',
            'CreatedAt': '2026-01-01T00:00:00Z',
            'LastUpdatedAt': '2026-01-01T00:00:00Z',
            'Favorite': 0,
            'Chapters': <Object?>[
              <String, Object?>{
                'Id': _chapterId,
                'SortNum': 1,
                'Title': '第 1 话',
                'CreatedAt': '2026-01-01T00:00:00Z',
                'PageCount': _pageSizes.length,
              },
            ],
          },
          'ReadPosition': null,
        });
      case 'GetComicContent':
        final skip = args['Skip']! as int;
        final take = args['Take']! as int;
        expect(take, 6);
        return decode(<String, Object?>{
          'Chapter': <String, Object?>{
            'Id': _chapterId,
            'BookId': _bookId,
            'Title': '第 1 话',
            'SortNum': 1,
            'Total': _pageSizes.length,
            'Skip': skip,
            'Images': <Object?>[
              for (
                var index = skip;
                index < skip + take && index < _pageSizes.length;
                index++
              )
                'https://img.example/page$index.webp?size=${_pageSizes[index]}',
            ],
          },
          'ReadPosition': null,
        });
      case 'SaveReadPosition':
        return decode(null);
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

Future<void> _open(
  WidgetTester tester, {
  bool dualPage = true,
  bool offsetFirstPage = false,
  bool statusPills = true,
  ReaderViewMode viewMode = ReaderViewMode.paged,
  ComicPagedDirection direction = ComicPagedDirection.ltr,
  Size size = const Size(1400, 800),
  FakeViewPadding padding = const FakeViewPadding(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);

  final settings = SettingsController(
    _MemoryStore(),
    AppSettings(
      comicReader: ReaderPreferences(
        dualPageEnabled: dualPage,
        dualPageOffsetEnabled: offsetFirstPage,
        statusPillsEnabled: statusPills,
        viewMode: viewMode,
      ),
      comicPagedDirection: direction,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(_FakeApi()),
        settingsControllerProvider.overrideWith((ref) => settings),
      ],
      child: const MaterialApp(
        home: ComicReaderScreen(bookId: _bookId, sortNum: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 往后翻一屏。点击热区在 PhotoView 上翻不动（见下方用例的说明），用滑动。
Future<void> _swipeForward(WidgetTester tester) async {
  await tester.fling(
    find.byType(PhotoViewGallery),
    const Offset(-600, 0),
    1500,
  );
  await tester.pumpAndSettle();
}

Finder _page(int index) => find.byWidgetPredicate(
  (widget) => widget is ContentImage && widget.url.contains('/page$index.webp'),
);

/// 页码胶囊上显示的当前页。
int _currentPage(WidgetTester tester) => tester
    .widget<ReaderStatusPills>(find.byType(ReaderStatusPills))
    .currentPage;

void main() {
  // 进度缓存是进程级的，上一个用例读到第几页会带进下一个用例。
  setUp(ReadPositionCache.clear);

  testWidgets('双页模式：两页并排，左页在前', (tester) async {
    await _open(tester);

    final left = tester.getRect(_page(0));
    final right = tester.getRect(_page(1));
    expect(left.right, lessThanOrEqualTo(right.left));
    expect(left.width, closeTo(right.width, 0.01));
    // 两页各占半屏，等比缩放后仍是原来的高宽比。
    expect(left.height / left.width, closeTo(1.5, 0.01));
    expect(_page(2), findsNothing);
  });

  testWidgets('错位双页先单独显示封面，后续再并排', (tester) async {
    await _open(tester, offsetFirstPage: true);

    expect(_page(0), findsOneWidget);
    expect(_page(1), findsNothing);

    await _swipeForward(tester);
    expect(_page(1), findsOneWidget);
    expect(_page(2), findsOneWidget);
  });

  testWidgets('右起时第一页摆在右边', (tester) async {
    await _open(tester, direction: ComicPagedDirection.rtl);

    expect(
      tester.getRect(_page(0)).left,
      greaterThan(tester.getRect(_page(1)).left),
    );
  });

  testWidgets('横跨两页的宽图独占一屏，配对跟着错开', (tester) async {
    await _open(tester);

    // 第 3 页的下一页是宽图，配不上对，自己占一屏。
    await _swipeForward(tester);
    expect(_page(2), findsOneWidget);
    expect(_page(3), findsNothing);

    // 宽图独占一屏，铺满整个屏宽。
    await _swipeForward(tester);
    final wide = tester.getRect(_page(3));
    // 一页占满整屏：比竖版页的半屏宽得多，高宽比仍是原图的。
    expect(wide.width, greaterThan(1400 / 2));
    expect(wide.height / wide.width, closeTo(1000 / 1600, 0.01));

    // 之后的页恢复两两成对。
    await _swipeForward(tester);
    expect(_page(4), findsOneWidget);
    expect(_page(5), findsOneWidget);
  });

  testWidgets('页码按屏首算：一屏两页时报前面那一页', (tester) async {
    await _open(tester);

    // 屏依次是 [0,1]、[2]、[3]、[4,5]，页码走屏首。
    expect(_currentPage(tester), 1);
    await _swipeForward(tester);
    expect(_currentPage(tester), 3);
    await _swipeForward(tester);
    expect(_currentPage(tester), 4);
    await _swipeForward(tester);
    expect(_currentPage(tester), 5);
  });

  testWidgets('进度落在屏中间时退回屏首', (tester) async {
    // 上次单栏读到第 2 页；它与第 1 页同屏，页码该报 1 而不是 2。
    ReadPositionCache.stage(
      _bookId,
      const BookReadPosition(chapterId: _chapterId, position: '2'),
    );
    await _open(tester);

    expect(_currentPage(tester), 1);
    expect(_page(0), findsOneWidget);
    expect(_page(1), findsOneWidget);
  });

  testWidgets('默认在角落摆页码胶囊', (tester) async {
    await _open(tester);

    expect(find.byType(ReaderStatusPills), findsOneWidget);
  });

  testWidgets('关掉页码胶囊后画面上不再叠这一层', (tester) async {
    await _open(tester, statusPills: false);

    expect(find.byType(ReaderStatusPills), findsNothing);
  });

  testWidgets('翻页模式避开状态栏、导航栏和页码胶囊', (tester) async {
    await _open(
      tester,
      dualPage: false,
      size: const Size(800, 800),
      padding: const FakeViewPadding(top: 40, bottom: 30),
    );

    final gallery = tester.getRect(find.byType(PhotoViewGallery));
    final pills = tester.getRect(find.byType(ReaderStatusPills));
    expect(gallery.top, 52);
    expect(gallery.bottom, 714);
    expect(pills.top, greaterThan(gallery.bottom));
  });

  testWidgets('滚动模式只避开状态栏并隐藏页码胶囊', (tester) async {
    await _open(
      tester,
      viewMode: ReaderViewMode.scroll,
      size: const Size(800, 800),
      padding: const FakeViewPadding(top: 40, bottom: 30),
    );

    final list = tester.getRect(find.byType(ListView));
    expect(list.top, 40);
    expect(list.bottom, 800);
    expect(find.byType(ReaderStatusPills), findsNothing);
  });

  testWidgets('关掉双页时一屏只摆一页', (tester) async {
    await _open(tester, dualPage: false);

    expect(_page(0), findsOneWidget);
    expect(_page(1), findsNothing);
  });

  testWidgets('屏幕竖着时一屏只摆一页', (tester) async {
    await _open(tester, size: const Size(800, 1400));

    expect(_page(0), findsOneWidget);
    expect(_page(1), findsNothing);
  });
}
