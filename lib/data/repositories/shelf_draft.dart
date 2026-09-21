import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/models.dart';

/// 书架草稿代数：纯同步函数，不依赖网络与 Riverpod。

/// 书架结构快照。
@immutable
class ShelfSnapshot {
  const ShelfSnapshot({required this.items});

  final List<ShelfItem> items;

  static const ShelfSnapshot empty = ShelfSnapshot(items: <ShelfItem>[]);

  ShelfDraft toDraft() => ShelfDraft(
    items: items
        .map((item) => item.copyWith(parents: List<String>.of(item.parents)))
        .toList(),
  );
}

/// 编辑中的书架草稿。
@immutable
class ShelfDraft {
  const ShelfDraft({required this.items});

  final List<ShelfItem> items;

  ShelfDraft copyWith({List<ShelfItem>? items}) =>
      ShelfDraft(items: items ?? this.items);
}

bool _sameParents(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// 判断某本书是否在书架中，快照与草稿共用。
bool shelfContainsBook(List<ShelfItem> items, int bookId) =>
    items.any((item) => item.isBook && item.bookId == bookId);

List<ShelfItem> sortShelfItems(List<ShelfItem> items) {
  final sorted = List<ShelfItem>.of(items);
  sorted.sort((a, b) {
    if (a.index != b.index) return a.index.compareTo(b.index);
    return a.parents.length.compareTo(b.parents.length);
  });
  return sorted;
}

/// 同一父路径下重新编号，保持顺序稳定。
List<ShelfItem> normalizeShelfIndexes(List<ShelfItem> items) {
  final nextIndexByParents = <String, int>{};
  return sortShelfItems(items).map((item) {
    final parentKey = jsonEncode(item.parents);
    final index = nextIndexByParents[parentKey] ?? 0;
    nextIndexByParents[parentKey] = index + 1;
    return item.copyWith(index: index);
  }).toList();
}

List<ShelfItem> shelfItemsAtPath(ShelfDraft draft, List<String> parents) =>
    sortShelfItems(
      draft.items.where((item) => _sameParents(item.parents, parents)).toList(),
    );

/// 校验路径上的每一层文件夹都存在，且父子关系与路径一致。
void _assertShelfPath(List<ShelfItem> items, List<String> parents) {
  for (var index = 0; index < parents.length; index += 1) {
    final id = parents[index];
    final expectedParents = parents.sublist(0, index);
    final exists = items.any(
      (item) =>
          !item.isBook &&
          item.folderId == id &&
          _sameParents(item.parents, expectedParents),
    );
    if (!exists) throw ArgumentError('目标文件夹已不存在。');
  }
}

ShelfItem? shelfFolderById(ShelfDraft draft, String id) {
  for (final item in draft.items) {
    if (!item.isBook && item.folderId == id) return item;
  }
  return null;
}

bool shelfDraftHasChanges(ShelfSnapshot snapshot, ShelfDraft draft) {
  String signature(List<ShelfItem> items) => jsonEncode(
    normalizeShelfIndexes(items).map((item) => item.encode()).toList(),
  );
  return signature(snapshot.items) != signature(draft.items);
}

int shelfSelectionBookCount(ShelfDraft draft, Set<String> keys) {
  final folderIds = draft.items
      .where((item) => !item.isBook && keys.contains(item.key))
      .map((item) => item.folderId!)
      .toSet();
  return draft.items.where((item) {
    if (!item.isBook) return false;
    if (keys.contains(item.key)) return true;
    return item.parents.any(folderIds.contains);
  }).length;
}

ShelfDraft createShelfFolder(
  ShelfDraft draft, {
  required String id,
  required String title,
  required List<String> parents,
  required String now,
}) {
  final name = title.trim();
  if (id.isEmpty || name.isEmpty || name == '根文件夹') {
    throw ArgumentError('请输入有效的文件夹名称。');
  }
  if (draft.items.any((item) => !item.isBook && item.folderId == id)) {
    throw ArgumentError('该文件夹已存在。');
  }
  _assertShelfPath(draft.items, parents);
  if (draft.items.any(
    (item) =>
        !item.isBook &&
        item.title == name &&
        _sameParents(item.parents, parents),
  )) {
    throw ArgumentError('这一层已有同名文件夹。');
  }
  return draft.copyWith(
    items: normalizeShelfIndexes(<ShelfItem>[
      ShelfItem.folder(
        id: id,
        index: -1,
        parents: List<String>.of(parents),
        updatedAt: now,
        title: name,
      ),
      ...draft.items,
    ]),
  );
}

ShelfDraft renameShelfFolder(
  ShelfDraft draft, {
  required String id,
  required String title,
  required String now,
}) {
  final folder = shelfFolderById(draft, id);
  if (folder == null) throw ArgumentError('该文件夹已不存在。');
  final name = title.trim();
  if (name.isEmpty || name == '根文件夹') {
    throw ArgumentError('请输入有效的文件夹名称。');
  }
  final parents = folder.parents;
  if (draft.items.any(
    (item) =>
        !item.isBook &&
        item.folderId != id &&
        item.title == name &&
        _sameParents(item.parents, parents),
  )) {
    throw ArgumentError('这一层已有同名文件夹。');
  }
  return draft.copyWith(
    items: draft.items.map((item) {
      if (item.isBook || item.folderId != id) return item;
      return item.copyWith(title: name, updatedAt: now);
    }).toList(),
  );
}

/// 删除文件夹：其中的内容提升到该文件夹所在的上一层，更深的层级关系保持不变。
ShelfDraft deleteShelfFolder(
  ShelfDraft draft, {
  required String id,
  required String now,
}) {
  final folder = shelfFolderById(draft, id);
  if (folder == null) throw ArgumentError('该文件夹已不存在。');
  final parents = folder.parents;
  // 提升上来的内容排在上一层末尾。
  var lastIndex = draft.items.fold<int>(
    -1,
    (maximum, item) =>
        _sameParents(item.parents, parents) && item.index > maximum
        ? item.index
        : maximum,
  );
  final items = <ShelfItem>[];
  for (final item in draft.items) {
    if (!item.isBook && item.folderId == id) continue;
    final depth = item.parents.indexOf(id);
    if (depth == -1) {
      items.add(item);
      continue;
    }
    // 从路径里摘掉这个文件夹，直接子项重新排到上一层末尾。
    final isDirectChild = depth == item.parents.length - 1;
    if (isDirectChild) lastIndex += 1;
    items.add(
      item.copyWith(
        parents: <String>[
          ...item.parents.sublist(0, depth),
          ...item.parents.sublist(depth + 1),
        ],
        index: isDirectChild ? lastIndex : item.index,
        updatedAt: now,
      ),
    );
  }
  return draft.copyWith(items: normalizeShelfIndexes(items));
}

/// 移出书架：选中文件夹时，其中所有层级的内容一并移出。
ShelfDraft removeShelfItems(ShelfDraft draft, {required Set<String> keys}) {
  if (keys.isEmpty) return draft;
  final folderIds = draft.items
      .where((item) => !item.isBook && keys.contains(item.key))
      .map((item) => item.folderId!)
      .toSet();
  final items = draft.items
      .where(
        (item) =>
            !keys.contains(item.key) && !item.parents.any(folderIds.contains),
      )
      .toList();
  if (items.length == draft.items.length) return draft;
  return draft.copyWith(items: normalizeShelfIndexes(items));
}

/// 移动到指定路径；移动文件夹时，它子树里所有条目的路径前缀一并重写。
ShelfDraft moveShelfItems(
  ShelfDraft draft, {
  required Set<String> keys,
  required List<String> destination,
  required String now,
}) {
  _assertShelfPath(draft.items, destination);
  if (keys.isEmpty) throw ArgumentError('请至少选择一个条目。');
  final selected = sortShelfItems(
    draft.items.where((item) => keys.contains(item.key)).toList(),
  );
  if (selected.length != keys.length) throw ArgumentError('所选条目已不存在。');

  final selectedFolders = <String>{
    for (final item in selected)
      if (!item.isBook) item.folderId!,
  };
  final moving = <ShelfItem>[];
  for (final item in selected) {
    // 已经在目标文件夹里。
    if (_sameParents(item.parents, destination)) continue;
    // 祖先也在移动列表里，跟着祖先一起走。
    if (item.parents.any(selectedFolders.contains)) continue;
    // 目标路径经过这个文件夹自己，移进去会把它从树上摘下来。
    if (!item.isBook && destination.contains(item.folderId)) {
      throw ArgumentError('不能把文件夹移动到它自己或它的下级里。');
    }
    moving.add(item);
  }
  if (moving.isEmpty) throw ArgumentError('所选条目已经在这个文件夹里了。');

  // 负数下标让移动过来的条目排在目标层开头，彼此保持原来的先后顺序。
  final position = <String, int>{
    for (var index = 0; index < moving.length; index += 1)
      moving[index].key: index - moving.length,
  };
  final movingFolders = <String>{
    for (final item in moving)
      if (!item.isBook) item.folderId!,
  };
  final items = draft.items.map((item) {
    final index = position[item.key];
    if (index != null) {
      return item.copyWith(
        index: index,
        parents: List<String>.of(destination),
        updatedAt: now,
      );
    }
    final anchor = item.parents.indexWhere(movingFolders.contains);
    if (anchor == -1) return item;
    return item.copyWith(
      parents: <String>[...destination, ...item.parents.sublist(anchor)],
      updatedAt: now,
    );
  }).toList();
  return draft.copyWith(items: normalizeShelfIndexes(items));
}

ShelfDraft reorderShelfSiblings(
  ShelfDraft draft, {
  required List<String> parents,
  required List<String> orderedKeys,
  required String now,
}) {
  final siblings = shelfItemsAtPath(draft, parents);
  final expected = siblings.map((item) => item.key).toSet();
  final ordered = orderedKeys.toSet();
  if (expected.length != orderedKeys.length ||
      ordered.length != orderedKeys.length ||
      expected.any((key) => !ordered.contains(key))) {
    throw ArgumentError('排序必须包含同层的每个条目。');
  }
  final indexes = <String, int>{
    for (var index = 0; index < orderedKeys.length; index += 1)
      orderedKeys[index]: index,
  };
  return draft.copyWith(
    items: draft.items.map((item) {
      if (!_sameParents(item.parents, parents)) return item;
      return item.copyWith(
        index: indexes[item.key] ?? item.index,
        updatedAt: now,
      );
    }).toList(),
  );
}
