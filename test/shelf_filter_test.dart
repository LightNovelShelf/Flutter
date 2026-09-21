import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/repositories/shelf_draft.dart';

const String _now = '2026-01-01T00:00:00Z';

ShelfItem _book(
  int id,
  ShelfItemType type, {
  List<String> parents = const <String>[],
}) => ShelfItem.book(
  type: type,
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

/// 根层：小说 1、漫画 2、文件夹 mixed（下级 sub 里有漫画 4）、文件夹 novels（只有小说 5）
ShelfDraft _draft() => ShelfDraft(
  items: <ShelfItem>[
    _book(1, ShelfItemType.novel),
    _book(2, ShelfItemType.comic),
    _folder('mixed'),
    _folder('novels'),
    _book(3, ShelfItemType.novel, parents: <String>['mixed']),
    _folder('sub', parents: <String>['mixed']),
    _book(4, ShelfItemType.comic, parents: <String>['mixed', 'sub']),
    _book(5, ShelfItemType.novel, parents: <String>['novels']),
  ],
);

void main() {
  test('不筛选时整层原样显示', () {
    final level = shelfLevelAt(_draft(), const <String>[]);
    expect(level.siblings.map((item) => item.key), <String>[
      'FOLDER:mixed',
      'FOLDER:novels',
      'NOVEL:1',
      'COMIC:2',
    ]);
  });

  test('只看漫画：书按类型留，文件夹按整棵子树判断', () {
    final level = shelfLevelAt(
      _draft(),
      const <String>[],
      type: ShelfItemType.comic,
    );

    // novels 子树里没有漫画，整个文件夹不出现；mixed 的漫画藏在孙层也算数
    expect(level.siblings.map((item) => item.key), <String>[
      'FOLDER:mixed',
      'COMIC:2',
    ]);

    final preview = level.folderPreviews['mixed']!;
    expect(preview.bookCount, 1);
    expect(preview.bookIds, <int>[4]);
    expect(preview.folderCount, 1);
  });

  test('只看小说：卡片统计不算被筛掉的漫画', () {
    final level = shelfLevelAt(
      _draft(),
      const <String>[],
      type: ShelfItemType.novel,
    );

    expect(level.siblings.map((item) => item.key), <String>[
      'FOLDER:mixed',
      'FOLDER:novels',
      'NOVEL:1',
    ]);
    // mixed 里只剩直接子级的小说 3，sub 只装漫画所以不计入
    expect(level.folderPreviews['mixed']!.bookCount, 1);
    expect(level.folderPreviews['mixed']!.folderCount, 0);
  });

  test('进到文件夹里筛选同样生效', () {
    final level = shelfLevelAt(_draft(), const <String>[
      'mixed',
    ], type: ShelfItemType.comic);

    expect(level.siblings.map((item) => item.key), <String>['FOLDER:sub']);
  });
}
