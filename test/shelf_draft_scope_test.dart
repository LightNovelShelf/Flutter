import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/endpoints.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/providers.dart';
import 'package:lightnovel/data/repositories/shelf_repository.dart';
import 'package:lightnovel/data/session/auth_controller.dart';
import 'package:lightnovel/features/shelf/shelf_editor_controller.dart';

const String _now = '2026-01-01T00:00:00Z';

ShelfItem _novel(int id, {List<String> parents = const <String>[]}) =>
    ShelfItem.book(
      type: ShelfItemType.novel,
      id: id,
      index: id,
      parents: parents,
      updatedAt: _now,
    );

ShelfItem _folder(String id, {List<String> parents = const <String>[]}) =>
    ShelfItem.folder(
      id: id,
      index: 0,
      parents: parents,
      updatedAt: _now,
      title: id,
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

  /// 根层：小说 1、小说 2、文件夹 f（里面有小说 3）
  List<ShelfItem> items = <ShelfItem>[
    _novel(1),
    _novel(2),
    _folder('f'),
    _novel(3, parents: <String>['f']),
  ];

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

/// 订阅后再读，免得 autoDispose 的层级 provider 读完就被回收。
List<String> _levelKeys(ProviderContainer container, List<String> parents) {
  final provider = shelfLevelProvider(shelfLevelKey(parents));
  container.listen(provider, (_, _) {});
  return container.read(provider).siblings.map((item) => item.key).toList();
}

void main() {
  late _Api api;
  late ProviderContainer container;
  late ShelfEditorController editor;

  setUp(() async {
    api = _Api();
    container = _container(api);
    addTearDown(container.dispose);
    await container.read(shelfProvider.future);
    editor = container.read(shelfEditorProvider.notifier);
  });

  test('未保存的移动立刻在目标层可见，原来那层不再有它', () {
    final root = container
        .read(shelfDraftProvider)!
        .items
        .firstWhere((item) => item.key == 'NOVEL:1');
    editor.beginSelection(root);
    editor.moveItems(keys: <String>{'NOVEL:1'}, destination: <String>['f']);

    // 移动过来的条目排在目标层开头。
    expect(_levelKeys(container, const <String>['f']), <String>[
      'NOVEL:1',
      'NOVEL:3',
    ]);
    expect(_levelKeys(container, const <String>[]), <String>[
      'FOLDER:f',
      'NOVEL:2',
    ]);
    // 草稿还没保存，服务端那份不动。
    expect(api.items.length, 4);
    expect(
      api.items.firstWhere((item) => item.key == 'NOVEL:1').parents,
      isEmpty,
    );
  });

  test('在子层新建的文件夹落在子层', () {
    editor.createFolder('新的', parents: const <String>['f']);

    final created = container
        .read(shelfDraftProvider)!
        .items
        .firstWhere((item) => !item.isBook && item.title == '新的');
    expect(created.parents, <String>['f']);
    expect(_levelKeys(container, const <String>['f']), contains(created.key));
    expect(
      _levelKeys(container, const <String>[]),
      isNot(contains(created.key)),
    );
  });

  test('子层的改动让整个书架都算有未保存改动', () {
    expect(container.read(shelfDirtyProvider), isFalse);
    editor.createFolder('新的', parents: const <String>['f']);
    expect(container.read(shelfDirtyProvider), isTrue);

    editor.discard();
    expect(container.read(shelfDirtyProvider), isFalse);
    expect(_levelKeys(container, const <String>['f']), <String>['NOVEL:3']);
  });

  test('层级派生数据按路径记忆化，草稿没换就不重算', () {
    final provider = shelfLevelProvider(shelfLevelKey(const <String>[]));
    container.listen(provider, (_, _) {});
    final first = container.read(provider);
    expect(identical(container.read(provider), first), isTrue);

    editor.createFolder('新的', parents: const <String>['f']);
    expect(identical(container.read(provider), first), isFalse);
  });
}
