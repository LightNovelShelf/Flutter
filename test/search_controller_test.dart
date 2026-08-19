import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/search/search_providers.dart';

BookListItem _book(int id) => BookListItem(
  id: id,
  type: BookType.novel,
  title: '书 $id',
  seriesTitle: null,
  coverUrl: '',
  coverPlaceholder: null,
  authorName: null,
  lastUpdatedAt: DateTime(2026),
  level: null,
  interiorLevel: null,
  category: null,
);

/// 只实现搜索接口，其余成员用 noSuchMethod 兜住（调到即报错，说明用错了接口）。
class _FakeApi implements ApiClient {
  _FakeApi(this.responder);

  final Future<BookListPage> Function(BookSearchRequest request) responder;

  @override
  Future<BookListPage> searchNovelBooks(
    BookSearchRequest request, {
    CancelToken? cancelToken,
  }) => responder(request);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// 搜索历史要读键值存储，测试里不需要，直接短路。
class _StubHistory extends SearchHistoryController {
  @override
  Future<List<String>> build() async => const <String>[];

  @override
  void add(String keyword) {}
}

void main() {
  test('切换搜索模式会先清空旧结果，让骨架屏接手', () async {
    var pending = Completer<BookListPage>()
      ..complete(
        BookListPage(page: 1, totalPages: 1, items: <BookListItem>[_book(1)]),
      );

    final container = ProviderContainer(
      overrides: <Override>[
        appSettingsProvider.overrideWithValue(const AppSettings()),
        apiClientProvider.overrideWithValue(
          _FakeApi((_) => pending.future),
        ),
        searchHistoryProvider.overrideWith(_StubHistory.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(bookSearchProvider, (_, _) {}, fireImmediately: true);
    final controller = container.read(bookSearchProvider.notifier);

    controller.submit('魔法');
    await pumpEventQueue();
    expect(container.read(bookSearchProvider).items.length, 1);
    expect(container.read(bookSearchProvider).loading, isFalse);

    // 新一轮请求挂起，此时状态必须是「加载中 + 无结果」，否则界面会停留在旧结果上。
    pending = Completer<BookListPage>();
    controller.setMode(BookSearchMode.title);
    final switching = container.read(bookSearchProvider);
    expect(switching.loading, isTrue);
    expect(switching.items, isEmpty);
    expect(switching.page, 1);
    expect(switching.totalPages, 1);

    pending.complete(
      BookListPage(page: 1, totalPages: 1, items: <BookListItem>[_book(2)]),
    );
    await pumpEventQueue();
    final done = container.read(bookSearchProvider);
    expect(done.loading, isFalse);
    expect(done.items.map((item) => item.id), <int>[2]);
  });

  test('提交新关键词同样清空旧结果', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        appSettingsProvider.overrideWithValue(const AppSettings()),
        apiClientProvider.overrideWithValue(
          _FakeApi(
            (request) async => BookListPage(
              page: 1,
              totalPages: 1,
              items: <BookListItem>[_book(request.keywords.length)],
            ),
          ),
        ),
        searchHistoryProvider.overrideWith(_StubHistory.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(bookSearchProvider, (_, _) {}, fireImmediately: true);
    final controller = container.read(bookSearchProvider.notifier);

    controller.submit('a');
    await pumpEventQueue();
    expect(container.read(bookSearchProvider).items.length, 1);

    controller.submit('abc');
    final switching = container.read(bookSearchProvider);
    expect(switching.loading, isTrue);
    expect(switching.items, isEmpty);

    await pumpEventQueue();
    expect(container.read(bookSearchProvider).items.single.id, 3);
  });
}
