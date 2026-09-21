import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/repositories/shelf_draft.dart';

const String _now = '2026-01-01T00:00:00Z';

ShelfItem _book(int id, {List<String> parents = const <String>[]}) =>
    ShelfItem.book(id: id, index: id, parents: parents, updatedAt: _now);

ShelfItem _folder(
  String id, {
  int index = 0,
  List<String> parents = const <String>[],
}) => ShelfItem.folder(
  id: id,
  index: index,
  parents: parents,
  updatedAt: _now,
  title: id,
);

ShelfDraft _draft(List<ShelfItem> items) =>
    ShelfDraft(items: items, version: '1');

ShelfItem _find(ShelfDraft draft, String key) =>
    draft.items.firstWhere((item) => item.key == key);

bool _has(ShelfDraft draft, String key) =>
    draft.items.any((item) => item.key == key);

void main() {
  // a/b/c：三层文件夹，每层放一本书。
  ShelfDraft nested() => _draft(<ShelfItem>[
    _folder('a'),
    _folder('b', parents: <String>['a']),
    _folder('c', parents: <String>['a', 'b']),
    _book(1),
    _book(2, parents: <String>['a']),
    _book(3, parents: <String>['a', 'b']),
    _book(4, parents: <String>['a', 'b', 'c']),
  ]);

  group('createShelfFolder', () {
    test('建在指定路径下', () {
      final next = createShelfFolder(
        nested(),
        id: 'new',
        title: '新建',
        parents: <String>['a', 'b'],
        now: _now,
      );
      expect(_find(next, 'FOLDER:new').parents, <String>['a', 'b']);
      // 排在那一层的开头。
      expect(_find(next, 'FOLDER:new').index, 0);
    });

    test('同层重名拒绝，不同层同名放行', () {
      final draft = nested();
      expect(
        () => createShelfFolder(
          draft,
          id: 'new',
          title: 'b',
          parents: <String>['a'],
          now: _now,
        ),
        throwsArgumentError,
      );
      final next = createShelfFolder(
        draft,
        id: 'new',
        title: 'b',
        parents: <String>['a', 'b'],
        now: _now,
      );
      expect(_find(next, 'FOLDER:new').parents, <String>['a', 'b']);
    });

    test('路径上的文件夹不存在时拒绝', () {
      expect(
        () => createShelfFolder(
          nested(),
          id: 'new',
          title: '新建',
          parents: <String>['a', 'missing'],
          now: _now,
        ),
        throwsArgumentError,
      );
    });
  });

  test('renameShelfFolder 只跟同层查重', () {
    final draft = nested();
    // c 在 a/b 下，b 在 a 下，改名互不冲突。
    final next = renameShelfFolder(draft, id: 'c', title: 'b', now: _now);
    expect(_find(next, 'FOLDER:c').title, 'b');
    expect(
      () => renameShelfFolder(next, id: 'b', title: 'a', now: _now),
      returnsNormally,
    );
  });

  group('deleteShelfFolder', () {
    test('内容提升到上一层，更深的层级保持', () {
      final next = deleteShelfFolder(nested(), id: 'b', now: _now);
      expect(_has(next, 'FOLDER:b'), isFalse);
      // 直接子项升到 a 下。
      expect(_find(next, 'BOOK:3').parents, <String>['a']);
      expect(_find(next, 'FOLDER:c').parents, <String>['a']);
      // c 里的书仍在 c 里。
      expect(_find(next, 'BOOK:4').parents, <String>['a', 'c']);
    });

    test('提升上来的内容排在上一层原有内容之后', () {
      final next = deleteShelfFolder(nested(), id: 'b', now: _now);
      final level = shelfItemsAtPath(next, <String>[
        'a',
      ]).map((item) => item.key).toList();
      expect(level.first, 'BOOK:2');
      expect(level.sublist(1), containsAll(<String>['BOOK:3', 'FOLDER:c']));
    });
  });

  test('removeShelfItems 级联移出整棵子树', () {
    final next = removeShelfItems(nested(), keys: <String>{'FOLDER:b'});
    expect(_has(next, 'FOLDER:b'), isFalse);
    expect(_has(next, 'FOLDER:c'), isFalse);
    expect(_has(next, 'BOOK:3'), isFalse);
    expect(_has(next, 'BOOK:4'), isFalse);
    expect(_has(next, 'BOOK:2'), isTrue);
  });

  group('moveShelfItems', () {
    test('移动文件夹时重写子树的路径前缀', () {
      final draft = _draft(<ShelfItem>[
        _folder('a'),
        _folder('b', index: 1),
        _folder('c', parents: <String>['b']),
        _book(1, parents: <String>['b']),
        _book(2, parents: <String>['b', 'c']),
      ]);
      final next = moveShelfItems(
        draft,
        keys: <String>{'FOLDER:b'},
        destination: <String>['a'],
        now: _now,
      );
      expect(_find(next, 'FOLDER:b').parents, <String>['a']);
      expect(_find(next, 'FOLDER:c').parents, <String>['a', 'b']);
      expect(_find(next, 'BOOK:1').parents, <String>['a', 'b']);
      expect(_find(next, 'BOOK:2').parents, <String>['a', 'b', 'c']);
    });

    test('移动到目标层开头，并保持彼此的先后顺序', () {
      final draft = _draft(<ShelfItem>[
        _folder('a'),
        _book(1, parents: <String>['a']),
        _book(2),
        _book(3),
      ]);
      final next = moveShelfItems(
        draft,
        keys: <String>{'BOOK:2', 'BOOK:3'},
        destination: <String>['a'],
        now: _now,
      );
      expect(
        shelfItemsAtPath(next, <String>['a']).map((item) => item.key).toList(),
        <String>['BOOK:2', 'BOOK:3', 'BOOK:1'],
      );
    });

    test('拒绝把文件夹移进它自己或它的下级', () {
      final draft = nested();
      expect(
        () => moveShelfItems(
          draft,
          keys: <String>{'FOLDER:a'},
          destination: <String>['a', 'b'],
          now: _now,
        ),
        throwsArgumentError,
      );
    });

    test('祖先与后代同时选中时，后代跟着祖先走一次', () {
      final next = moveShelfItems(
        nested(),
        keys: <String>{'FOLDER:b', 'BOOK:3'},
        destination: const <String>[],
        now: _now,
      );
      expect(_find(next, 'FOLDER:b').parents, isEmpty);
      expect(_find(next, 'BOOK:3').parents, <String>['b']);
    });
  });
}
