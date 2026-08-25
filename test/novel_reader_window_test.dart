import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/repositories/read_position_cache.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/reader/novel_reader_screen.dart';
import 'package:lightnovel/features/reader/widgets/reader_content_view.dart';
import 'package:lightnovel/features/reader/widgets/reader_page_body.dart';
import 'package:lightnovel/features/reader/widgets/reader_status_pills.dart';

import 'support/reader_screen.dart';

/// 预渲染窗口：阅读器常驻当前章与前后各一章，跨章翻页复用预渲染结果。
const int _bookId = 7;
const int _totalChapters = 6;

/// [columns] 给定时按纯图片段落造章，一张图片正好占一栏，栏数完全可控；
/// 否则按段落造章。
Map<String, dynamic> _chapterResponse(
  int sortNum,
  int paragraphs,
  int? columns,
  bool longSingleBlock,
) => <String, dynamic>{
  'Chapter': <String, dynamic>{
    'Id': 100 + sortNum,
    'BookId': _bookId,
    'Title': '第$sortNum章',
    'Content': longSingleBlock
        ? '<p>${'第$sortNum章正文' * 500}</p>'
        : columns == null
        ? List<String>.generate(
            paragraphs,
            (index) =>
                '<p>第$sortNum章第$index段 这是一段用来撑开分页的正文，'
                '长度足够触发换行，好让每一页里都落进若干行。</p>',
          ).join()
        : List<String>.generate(
            columns,
            (index) =>
                '<p><img src="https://img.example/c$sortNum-$index.webp'
                '?size=1000x700"/></p>',
          ).join(),
    'Font': null,
    'SortNum': sortNum,
    'Chapters': List<String>.generate(
      _totalChapters,
      (index) => '第${index + 1}章',
    ),
    'CanEdit': false,
  },
  'ReadPosition': null,
};

class _FakeApi extends ApiClient {
  _FakeApi({
    this.latency = Duration.zero,
    this.paragraphs = 12,
    this.columnsByChapter = const <int, int>{},
    this.longSingleBlock = false,
  }) : super(
         signalR: SignalRConnection(
           endpoint: 'http://localhost/hub',
           accessTokenFactory: () async => null,
         ),
         scheduler: RateLimitRequestScheduler(),
         headers: () async => const <String, String>{},
       );

  /// 单次请求的模拟延迟，用于模拟预渲染的网络往返。
  final Duration latency;

  /// 每章的段数，正文按它撑开栏数。
  final int paragraphs;

  /// 指定了栏数的章，按纯图片段落造，栏数精确可控。
  final Map<int, int> columnsByChapter;
  final bool longSingleBlock;
  final List<int> requested = <int>[];
  final List<(int, String)> saved = <(int, String)>[];

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    final args = params as Map<String, Object?>;
    switch (methodName) {
      case 'GetNovelContent':
        final sortNum = args['SortNum']! as int;
        requested.add(sortNum);
        await Future<void>.delayed(latency);
        if (cancelToken?.isCancelled ?? false) {
          throw const RequestCancelledError();
        }
        return decode(
          _chapterResponse(
            sortNum,
            paragraphs,
            columnsByChapter[sortNum],
            longSingleBlock,
          ),
        );
      case 'SaveReadPosition':
        saved.add((args['Cid']! as int, args['XPath']! as String));
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

/// 翻页条内渲染的正文，排除测量层中的同名文本。
Finder _pageText(String text) => find.descendant(
  of: find.byType(PageView),
  matching: find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  ),
);

/// 屏幕中线所在页的 key（`reader-page-<章>-<页>`），无页覆盖中线时返回 null。
String? _visiblePage(WidgetTester tester) {
  final centerX =
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'reader-page-',
                ),
          )
          .evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    if (left <= centerX && left + box.size.width > centerX) {
      return (element.widget.key! as ValueKey<String>).value;
    }
  }
  return null;
}

Future<_FakeApi> _open(
  WidgetTester tester, {
  int sortNum = 2,
  bool prerender = true,
  bool statusPills = true,
  bool dualPage = false,
  int paragraphs = 12,
  Map<int, int> columnsByChapter = const <int, int>{},
  Duration latency = Duration.zero,
  bool scroll = false,
  bool longSingleBlock = false,
}) async {
  final api = _FakeApi(
    latency: latency,
    paragraphs: paragraphs,
    columnsByChapter: columnsByChapter,
    longSingleBlock: longSingleBlock,
  );
  final settings = SettingsController(
    _MemoryStore(),
    AppSettings(
      readerPrerenderAdjacent: prerender,
      novelReader: ReaderPreferences(
        statusPillsEnabled: statusPills,
        viewMode: scroll ? ReaderViewMode.scroll : ReaderViewMode.paged,
        dualPageEnabled: dualPage,
      ),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api),
        settingsControllerProvider.overrideWith((ref) => settings),
      ],
      child: MaterialApp(
        home: NovelReaderScreen(bookId: _bookId, sortNum: sortNum),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

/// 加载栏一直在转圈，`pumpAndSettle` 会等不到静止，只能推固定帧数。
Future<void> _spin(WidgetTester tester, [int frames = 20]) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  // 进度缓存是进程级的，上一个用例读到第几页会带进下一个用例。
  setUp(ReadPositionCache.clear);

  testWidgets('单页打开一章：屏首屏尾都是这一章，前后各备一章', (tester) async {
    final api = await _open(tester);

    expect(api.requested.first, 2);
    expect(api.requested.toSet(), <int>{1, 2, 3});
  });

  testWidgets('关掉预渲染就只取当前章', (tester) async {
    final api = await _open(tester, prerender: false);

    expect(api.requested, <int>[2]);
  });

  testWidgets('首章不会去取不存在的上一章', (tester) async {
    final api = await _open(tester, sortNum: 1);

    expect(api.requested.toSet(), <int>{1, 2});
  });

  testWidgets('滚动模式跨章按方向落在目标章边界', (tester) async {
    await _open(tester, scroll: true, longSingleBlock: true);

    final current = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    expect(current.pixels, closeTo(current.minScrollExtent, 0.5));

    final view = tester.getRect(find.byType(ReaderContentView));
    await tester.tapAt(Offset(view.center.dx, view.top + view.height * 0.1));
    await tester.pumpAndSettle();

    final previous = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    expect(previous.maxScrollExtent, greaterThan(0));
    expect(previous.pixels, closeTo(previous.maxScrollExtent, 0.5));

    final previousView = tester.getRect(find.byType(ReaderContentView));
    await tester.tapAt(
      Offset(
        previousView.center.dx,
        previousView.bottom - previousView.height * 0.1,
      ),
    );
    await tester.pumpAndSettle();

    final next = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    expect(next.pixels, closeTo(next.minScrollExtent, 0.5));
  });

  testWidgets('双页开预加载：一屏跨两章时下一屏那章也已备好，翻过去左栏不转圈', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 每章都只占一栏：一屏摆第 1、2 章，翻一屏就到第 3 章。
    final api = await _open(tester, sortNum: 1, dualPage: true, paragraphs: 1);

    expect(find.byKey(readerPageBodyKey(1, 0)), findsOneWidget);
    expect(find.byKey(readerPageBodyKey(2, 0)), findsOneWidget);
    // 屏上摆着第 2 章，第 3 章也得提前备好，否则翻过去左栏就是加载栏。
    expect(api.requested.toSet(), <int>{1, 2, 3});

    await tester.tapAt(const Offset(1100, 400));
    await _spin(tester);

    // 左栏是备好的第 3 章，只有更外面的右栏可能还在转圈。
    expect(readerScreenSlots(tester, columns: 2).first, '3-0');
  });

  testWidgets('双页：栏数 1、1、1、2 的书按栏翻，跨章那一屏不闪回上一栏', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 前三章各一栏、第 4 章两栏：屏应当是 <1,2>、<3,4上>、<4下,5>。
    // 走到第三屏时第 1 章会被移出窗口，屏上那两栏不许跟着重新配对。
    await _open(
      tester,
      sortNum: 1,
      dualPage: true,
      columnsByChapter: const <int, int>{1: 1, 2: 1, 3: 1, 4: 2, 5: 1, 6: 1},
    );
    await _spin(tester, 40);
    expect(readerScreenSlots(tester, columns: 2), <String>['1-0', '2-0']);

    await tester.tapAt(const Offset(1100, 400));
    await _spin(tester, 40);
    expect(readerScreenSlots(tester, columns: 2), <String>['3-0', '4-0']);

    await tester.tapAt(const Offset(1100, 400));
    await _spin(tester, 40);
    expect(readerScreenSlots(tester, columns: 2), <String>['4-1', '5-0']);

    // 页码按屏首那一章算：第 4 章第 2 栏。
    final pills = tester.widget<ReaderStatusPills>(
      find.byType(ReaderStatusPills),
    );
    expect(
      (pills.currentChapter, pills.currentPage, pills.totalPages),
      (4, 2, 2),
    );

    // 再翻回去，还是原来那两屏。
    await tester.tapAt(const Offset(100, 400));
    await _spin(tester, 40);
    expect(readerScreenSlots(tester, columns: 2), <String>['3-0', '4-0']);
  });

  testWidgets('单页关掉预加载：翻过末页才请求下一章，转圈等它到位', (tester) async {
    final api = await _open(tester, prerender: false);
    expect(api.requested, <int>[2]);

    // 读到本章末页为止都不该去取下一章。
    for (var turn = 0; turn < 40; turn++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
      if (_pageText('第2章第11段').evaluate().isNotEmpty) break;
    }
    expect(api.requested, <int>[2]);

    await tester.tapAt(const Offset(700, 300));
    await tester.pump();
    // 请求发出的那一刻正文换成加载栏。
    expect(api.requested, <int>[2, 3]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _spin(tester, 40);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_pageText('第3章第0段'), findsWidgets);
    // 落进第 3 章后仍然不预取第 4 章。
    expect(api.requested, <int>[2, 3]);
  });

  testWidgets('双页关掉预加载：右栏空着就去取下一章', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 一段正文的章只占一栏，进阅读器时右栏就是空的。
    final api = await _open(
      tester,
      prerender: false,
      dualPage: true,
      paragraphs: 1,
    );
    await _spin(tester);

    expect(api.requested, <int>[2, 3]);
    await _spin(tester, 40);

    // 取回来的第 3 章摆在右栏，当前章还是第 2 章。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(readerPageBodyKey(2, 0)), findsOneWidget);
    expect(find.byKey(readerPageBodyKey(3, 0)), findsOneWidget);
    expect(_pageText('第3章第0段'), findsWidgets);
  });

  testWidgets('取过的章一直留在内存：来回翻不重复请求', (tester) async {
    final api = await _open(tester, sortNum: 3);

    Future<void> turn(Offset at) async {
      await tester.tapAt(at);
      await tester.pumpAndSettle();
    }

    // 往前翻进第 2 章，再一路翻回第 4 章，沿途每一章都进过窗口又出去。
    for (var step = 0; step < 40; step++) {
      await turn(const Offset(100, 300));
      if (_pageText('第2章第0段').evaluate().isNotEmpty) break;
    }
    expect(_pageText('第2章第0段'), findsWidgets);
    for (var step = 0; step < 80; step++) {
      await turn(const Offset(700, 300));
      if (_pageText('第4章第0段').evaluate().isNotEmpty) break;
    }
    expect(_pageText('第4章第0段'), findsWidgets);

    expect(api.requested, hasLength(api.requested.toSet().length));
  });

  testWidgets('跨章那一下页码胶囊就跟到新章，不停在上一章的页数上', (tester) async {
    await _open(tester);

    // 第 2 章的页数，跨章后胶囊不该还是它。
    final pages = tester
        .widget<ReaderStatusPills>(find.byType(ReaderStatusPills))
        .totalPages;
    expect(pages, greaterThan(1));

    for (var turn = 0; turn < 40; turn++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
      if (_pageText('第3章第0段').evaluate().isNotEmpty) break;
    }

    final pills = tester.widget<ReaderStatusPills>(
      find.byType(ReaderStatusPills),
    );
    expect(_pageText('第3章第0段'), findsWidgets);
    expect(pills.currentChapter, 3);
    expect(pills.currentPage, 1);
    expect(pills.totalPages, pages);
  });

  testWidgets('翻过末页进下一章：不重取正文、不出加载态，窗口跟着挪一格', (tester) async {
    final api = await _open(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_pageText('第2章第0段'), findsWidgets);

    for (var turn = 0; turn < 40; turn++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
      if (_pageText('第3章第0段').evaluate().isNotEmpty) break;
    }

    expect(_pageText('第3章第0段'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 第 3 章仅预渲染时请求过一次。
    expect(api.requested.where((sortNum) => sortNum == 3), hasLength(1));
    // 屏首挪到第 3 章后，屏尾的下一章第 4 章跟着备好。
    expect(api.requested.toSet(), <int>{1, 2, 3, 4});
    // 102 是第 2 章的 id，离开该章时提交进度。
    expect(api.saved.map((entry) => entry.$1), contains(102));
  });

  testWidgets('往后跨章的每一帧都不许闪到别的页', (tester) async {
    // 加延迟使预渲染在跨章之后才落地，覆盖翻页的那几帧。
    await _open(tester, latency: const Duration(milliseconds: 300));

    final seen = <String>[];
    void record() {
      final page = _visiblePage(tester);
      if (page != null && (seen.isEmpty || seen.last != page)) seen.add(page);
    }

    record();
    for (var turn = 0; turn < 12; turn++) {
      await tester.tapAt(const Offset(700, 300));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        record();
      }
      if (seen.last.startsWith('reader-page-3-')) break;
    }

    final crossing = seen.indexWhere(
      (page) => page.startsWith('reader-page-3-'),
    );
    expect(crossing, greaterThan(0), reason: '没能翻进下一章：$seen');
    expect(seen.sublist(0, crossing), <String>[
      for (var page = 0; page < crossing; page++) 'reader-page-2-$page',
    ]);
    expect(seen.sublist(crossing).toSet(), <String>{'reader-page-3-0'});
  });

  testWidgets('往前跨章的每一帧都不许闪到别的页', (tester) async {
    // 反向跨章后窗口平移，更远那章中途才就绪并使翻页条整体后移。
    await _open(tester, sortNum: 3, latency: const Duration(milliseconds: 300));

    final seen = <String>[];
    void record() {
      final page = _visiblePage(tester);
      if (page != null && (seen.isEmpty || seen.last != page)) seen.add(page);
    }

    record();
    await tester.tapAt(const Offset(100, 300));
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      record();
    }

    expect(seen.first, 'reader-page-3-0');
    // 跨章后应停在上一章末页，中途就绪的更远章节不改变当前页。
    expect(seen.sublist(1), isNotEmpty);
    expect(seen.sublist(1).toSet(), hasLength(1));
    expect(seen.last, startsWith('reader-page-2-'));
  });

  testWidgets('关掉页码胶囊后页底留白还给正文', (tester) async {
    Future<(double padding, double height)> layout({
      required bool statusPills,
    }) async {
      await _open(tester, statusPills: statusPills);
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      final page = tester.getRect(find.byKey(readerPageBodyKey(2, 0)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      return (view.padding.bottom, page.height);
    }

    final (pillPadding, pillHeight) = await layout(statusPills: true);
    final (barePadding, bareHeight) = await layout(statusPills: false);

    // 页底给胶囊留的 56 点缩回普通间距 12 点。
    expect(pillPadding, 56);
    expect(barePadding, 12);
    // 多出来的高度落到正文上，页尾能多排一行。
    expect(bareHeight, greaterThan(pillHeight));
  });
}
