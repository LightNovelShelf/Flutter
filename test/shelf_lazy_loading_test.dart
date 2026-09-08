import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/endpoints.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/repositories/shelf_books.dart';
import 'package:lightnovel/data/repositories/shelf_repository.dart';
import 'package:lightnovel/data/session/auth_controller.dart';
import 'package:lightnovel/features/shelf/shelf_editor_controller.dart';
import 'package:lightnovel/features/shelf/widgets/shelf_tile.dart';

ShelfItem _book(int id, {List<String> parents = const []}) => ShelfItem.book(
  id: id,
  index: id,
  parents: parents,
  updatedAt: '2026-01-01T00:00:00Z',
);

class _Api extends ApiClient {
  _Api()
    : super(
        signalR: SignalRConnection(
          endpoint: 'http://localhost/hub',
          accessTokenFactory: () async => null,
        ),
        scheduler: RateLimitRequestScheduler(),
        headers: () async => const <String, String>{},
      );

  List<ShelfItem> items = List.generate(100, (index) => _book(index + 1));
  final batches = <List<int>>[];
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object?) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    switch (methodName) {
      case 'GetBookShelf':
        return decode({
          'data': items.map((item) => item.encode()).toList(),
          'ver': shelfStructVersion,
        });
      case 'SaveBookShelf':
        items = ((params! as Map<String, Object?>)['data']! as List)
            .map(ShelfItem.decode)
            .toList();
        return decode(null);
      case 'GetBookListByIds':
        final ids = (params! as Map<String, Object?>)['Ids']! as List<int>;
        batches.add(List.of(ids));
        await gate?.future;
        if (fail) throw StateError('offline');
        return decode([
          for (final id in ids)
            if (id != 99)
              {
                'Id': id,
                'Title': 'Book $id',
                'Cover': '/cover.png',
                'LastUpdatedAt': '2026-01-01T00:00:00Z',
              },
        ]);
      default:
        throw StateError(methodName);
    }
  }
}

ProviderContainer _container(_Api api) => ProviderContainer(
  overrides: [
    apiClientProvider.overrideWithValue(api),
    authSnapshotProvider.overrideWithValue(
      const AuthenticationSnapshot(status: AuthenticationStatus.authenticated),
    ),
  ],
);

void main() {
  test('加载、保存、收藏操作只请求书架结构', () async {
    final api = _Api();
    final container = _container(api);
    addTearDown(container.dispose);
    final snapshot = (await container.read(shelfProvider.future))!;
    final controller = container.read(shelfProvider.notifier);
    expect(await controller.contains(1), isTrue);
    await controller.save(snapshot.toDraft());
    expect(await controller.toggleBook(101), isTrue);
    expect(await controller.contains(101), isTrue);
    expect(api.batches, isEmpty);
  });

  test('相邻与并发查询合批，已加载和下架结果均缓存，失败可重试', () async {
    final api = _Api()..gate = Completer<void>();
    final cache = ShelfBookCache(api);
    addTearDown(cache.dispose);
    final first = cache.load(1);
    final missing = cache.load(99);
    await Future<void>.delayed(Duration.zero);
    final duplicate = cache.load(1);
    api.gate!.complete();
    expect((await first)?.id, 1);
    expect((await duplicate)?.id, 1);
    expect(await missing, isNull);
    expect(await cache.load(99), isNull);
    expect(api.batches, [
      [1, 99],
    ]);
    api.fail = true;
    await expectLater(cache.load(2), throwsStateError);
    api.fail = false;
    expect((await cache.load(2))?.id, 2);
    expect(api.batches, [
      [1, 99],
      [2],
      [2],
    ]);
  });

  testWidgets('卡片随滚动请求，返回已访问区域复用缓存', (tester) async {
    final api = _Api();
    final container = _container(api);
    addTearDown(container.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: GridView.builder(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 360,
              ),
              itemCount: api.items.length,
              itemBuilder: (_, index) => ShelfTile(
                editorKey: shelfEditorKey(const []),
                item: api.items[index],
                index: index,
                siblings: api.items,
                folder: null,
                tileWidth: 200,
                onOpenBook: (_) {},
                onOpenFolder: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = api.batches.expand((ids) => ids).toSet();
    expect(initial, contains(1));
    expect(initial, isNot(contains(50)));
    scroll.jumpTo(3600);
    await tester.pumpAndSettle();
    expect(api.batches.expand((ids) => ids), contains(41));
    final count = api.batches.length;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(api.batches.length, count);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件夹只请求排序后的前四本直接子书籍', (tester) async {
    final api = _Api();
    const folder = ShelfItem.folder(
      id: 'f',
      index: 0,
      parents: [],
      updatedAt: '',
      title: 'Folder',
    );
    api.items = [
      folder,
      for (var id = 1; id <= 10; id++) _book(id, parents: ['f']),
      _book(50, parents: ['f', 'nested']),
    ];
    final container = _container(api);
    addTearDown(container.dispose);
    final snapshot = (await container.read(shelfProvider.future))!;
    final editor = container.read(
      shelfEditorProvider(shelfEditorKey(const [])).notifier,
    );
    final preview = editor.level(snapshot.toDraft()).folderPreviews['f']!;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: ShelfTile(
                editorKey: shelfEditorKey(const []),
                item: folder,
                index: 0,
                siblings: const [folder],
                folder: preview,
                tileWidth: 200,
                onOpenBook: (_) {},
                onOpenFolder: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.batches, [
      [1, 2, 3, 4],
    ]);
    await container.read(shelfProvider.notifier).reload();
    await tester.pumpAndSettle();
    expect(api.batches, [
      [1, 2, 3, 4],
      [1, 2, 3, 4],
    ]);
    expect(tester.takeException(), isNull);
  });
}
