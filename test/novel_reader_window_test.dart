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

/// 预渲染窗口：阅读器常驻当前章与前后各一章，跨章翻页复用预渲染结果。
const int _bookId = 7;
const int _totalChapters = 5;

Map<String, dynamic> _chapterResponse(int sortNum) => <String, dynamic>{
  'Chapter': <String, dynamic>{
    'Id': 100 + sortNum,
    'BookId': _bookId,
    'Title': '第$sortNum章',
    'Content': List<String>.generate(
      12,
      (index) =>
          '<p>第$sortNum章第$index段 这是一段用来撑开分页的正文，'
          '长度足够触发换行，好让每一页里都落进若干行。</p>',
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
  _FakeApi({this.latency = Duration.zero})
    : super(
        signalR: SignalRConnection(
          endpoint: 'http://localhost/hub',
          accessTokenFactory: () async => null,
        ),
        scheduler: RateLimitRequestScheduler(),
        headers: () async => const <String, String>{},
      );

  /// 单次请求的模拟延迟，用于模拟预渲染的网络往返。
  final Duration latency;
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
        return decode(_chapterResponse(sortNum));
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
  Duration latency = Duration.zero,
}) async {
  final api = _FakeApi(latency: latency);
  final settings = SettingsController(
    _MemoryStore(),
    AppSettings(
      readerPrerenderAdjacent: prerender,
      readerStatusPillsEnabled: statusPills,
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

void main() {
  // 进度缓存是进程级的，上一个用例读到第几页会带进下一个用例。
  setUp(ReadPositionCache.clear);

  testWidgets('打开一章后前后各一章跟着预渲染', (tester) async {
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
    // 窗口平移后预渲染第 4 章。
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
