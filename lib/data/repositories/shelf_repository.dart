import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';

/// 书架快照：条目 + 已解析的书籍信息。
@immutable
class ShelfSnapshot {
  const ShelfSnapshot({
    required this.items,
    required this.books,
    required this.version,
  });

  final List<ShelfItem> items;
  final List<BookListItem> books;
  final String? version;

  static const ShelfSnapshot empty = ShelfSnapshot(
    items: <ShelfItem>[],
    books: <BookListItem>[],
    version: null,
  );

  Map<int, BookListItem> get bookById =>
      <int, BookListItem>{for (final book in books) book.id: book};

  ShelfDraft toDraft() => ShelfDraft(
        items: items
            .map((item) => item.copyWith(parents: List<String>.of(item.parents)))
            .toList(),
        version: version,
      );
}

/// 编辑中的书架草稿。
@immutable
class ShelfDraft {
  const ShelfDraft({required this.items, required this.version});

  final List<ShelfItem> items;
  final String? version;

  ShelfDraft copyWith({List<ShelfItem>? items}) =>
      ShelfDraft(items: items ?? this.items, version: version);
}

bool _sameParents(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

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

class ShelfFolderPath {
  const ShelfFolderPath({required this.id, required this.title, required this.parents});

  final String id;
  final String title;
  final List<String> parents;

  List<String> get path => <String>[...parents, id];
}

List<ShelfFolderPath> shelfFolderPaths(ShelfDraft draft) => sortShelfItems(
      draft.items.where((item) => !item.isBook).toList(),
    )
        .map(
          (item) => ShelfFolderPath(
            id: item.folderId!,
            title: item.title,
            parents: item.parents,
          ),
        )
        .toList();

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
  required String now,
}) {
  final name = title.trim();
  if (id.isEmpty || name.isEmpty || name == '根文件夹') {
    throw ArgumentError('请输入有效的文件夹名称。');
  }
  if (draft.items.any((item) => !item.isBook && item.folderId == id)) {
    throw ArgumentError('该文件夹已存在。');
  }
  if (draft.items.any((item) => !item.isBook && item.title == name)) {
    throw ArgumentError('已存在同名文件夹。');
  }
  return draft.copyWith(
    items: normalizeShelfIndexes(<ShelfItem>[
      ShelfItem.folder(
        id: id,
        index: -1,
        parents: const <String>[],
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
  final name = title.trim();
  if (name.isEmpty || name == '根文件夹') {
    throw ArgumentError('请输入有效的文件夹名称。');
  }
  if (draft.items
      .any((item) => !item.isBook && item.folderId != id && item.title == name)) {
    throw ArgumentError('已存在同名文件夹。');
  }
  var found = false;
  final items = draft.items.map((item) {
    if (item.isBook || item.folderId != id) return item;
    found = true;
    return item.copyWith(title: name, updatedAt: now);
  }).toList();
  if (!found) throw ArgumentError('该文件夹已不存在。');
  return draft.copyWith(items: items);
}

/// 删除文件夹：子书籍提升到根目录尾部，子文件夹解除该层父级。
ShelfDraft deleteShelfFolder(
  ShelfDraft draft, {
  required String id,
  required String now,
}) {
  if (!draft.items.any((item) => !item.isBook && item.folderId == id)) {
    throw ArgumentError('该文件夹已不存在。');
  }
  var rootIndex = draft.items.fold<int>(
    -1,
    (maximum, item) =>
        item.parents.isEmpty ? (item.index > maximum ? item.index : maximum) : maximum,
  );
  final items = <ShelfItem>[];
  for (final item in draft.items) {
    if (!item.isBook && item.folderId == id) continue;
    if (!item.parents.contains(id)) {
      items.add(item);
      continue;
    }
    if (item.isBook) {
      rootIndex += 1;
      items.add(
        item.copyWith(
          index: rootIndex,
          parents: const <String>[],
          updatedAt: now,
        ),
      );
      continue;
    }
    items.add(
      item.copyWith(
        parents: item.parents.where((parent) => parent != id).toList(),
        updatedAt: now,
      ),
    );
  }
  return draft.copyWith(items: normalizeShelfIndexes(items));
}

ShelfDraft removeShelfItems(
  ShelfDraft draft, {
  required Set<String> keys,
  required String now,
}) {
  final folderIds = draft.items
      .where((item) => !item.isBook && keys.contains(item.key))
      .map((item) => item.folderId!)
      .toList();
  final bookKeys = keys.where((key) => key.startsWith('BOOK:')).toSet();
  var next = draft.copyWith(
    items: draft.items.where((item) => !bookKeys.contains(item.key)).toList(),
  );
  for (final id in folderIds) {
    if (next.items.any((item) => !item.isBook && item.folderId == id)) {
      next = deleteShelfFolder(next, id: id, now: now);
    }
  }
  return next.copyWith(items: normalizeShelfIndexes(next.items));
}

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

ShelfDraft moveShelfBooks(
  ShelfDraft draft, {
  required List<int> bookIds,
  required List<String> destination,
  required String now,
}) {
  _assertShelfPath(draft.items, destination);
  final ids = bookIds.toSet();
  if (ids.isEmpty) throw ArgumentError('请至少选择一本书。');
  final selected = sortShelfItems(
    draft.items.where((item) => item.isBook && ids.contains(item.bookId)).toList(),
  );
  if (selected.length != ids.length) throw ArgumentError('所选书籍已不存在。');
  final position = <int, int>{
    for (var index = 0; index < selected.length; index += 1)
      selected[index].bookId!: index - selected.length,
  };
  final items = draft.items.map((item) {
    final index = item.isBook ? position[item.bookId] : null;
    if (index == null) return item;
    return item.copyWith(
      index: index,
      parents: List<String>.of(destination),
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
      return item.copyWith(index: indexes[item.key] ?? item.index, updatedAt: now);
    }).toList(),
  );
}

/// 书架仓库：加载、保存（串行队列 + 代际号）与单本增删。
class ShelfController extends AsyncNotifier<ShelfSnapshot?> {
  ApiClient get _api => ref.read(apiClientProvider);

  int _mutationGeneration = 0;
  Future<void> _saveQueue = Future<void>.value();

  @override
  Future<ShelfSnapshot?> build() async {
    final snapshot = ref.watch(authSnapshotProvider);
    if (!snapshot.isAuthenticated) return null;
    return _load();
  }

  Future<ShelfSnapshot> _hydrate(List<ShelfItem> items, String? version) async {
    final bookIds = items
        .where((item) => item.isBook)
        .map((item) => item.bookId!)
        .toList();
    final books = <BookListItem>[];
    for (var index = 0; index < bookIds.length; index += 24) {
      books.addAll(
        await _api.getBookListByIds(
          bookIds.sublist(index, (index + 24).clamp(0, bookIds.length)),
        ),
      );
    }
    return ShelfSnapshot(
      items: sortShelfItems(items),
      books: books,
      version: version,
    );
  }

  Future<ShelfSnapshot> _load() async {
    await _saveQueue;
    final generation = _mutationGeneration;
    final shelf = await _api.getBookShelf();
    final snapshot = await _hydrate(shelf.items, shelf.version);
    if (generation != _mutationGeneration) {
      return state.valueOrNull ?? snapshot;
    }
    return snapshot;
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      if (!ref.read(authSnapshotProvider).isAuthenticated) return null;
      return _load();
    });
  }

  Future<ShelfSnapshot> save(ShelfDraft draft) {
    final generation = ++_mutationGeneration;
    final normalized = ShelfDraft(
      items: normalizeShelfIndexes(draft.items),
      version: draft.version,
    );
    final operation = _saveQueue.then((_) async {
      await _api.saveBookShelf(
        UserShelf(version: normalized.version, items: normalized.items),
      );
      final knownBooks = <int, BookListItem>{
        for (final book in state.valueOrNull?.books ?? const <BookListItem>[])
          book.id: book,
      };
      final missingIds = normalized.items
          .where((item) => item.isBook && !knownBooks.containsKey(item.bookId))
          .map((item) => item.bookId!)
          .toList();
      for (var index = 0; index < missingIds.length; index += 24) {
        for (final book in await _api.getBookListByIds(
          missingIds.sublist(index, (index + 24).clamp(0, missingIds.length)),
        )) {
          knownBooks[book.id] = book;
        }
      }
      final nextIds = normalized.items
          .where((item) => item.isBook)
          .map((item) => item.bookId!)
          .toSet();
      final snapshot = ShelfSnapshot(
        items: normalized.items,
        books: knownBooks.values.where((book) => nextIds.contains(book.id)).toList(),
        version: normalized.version,
      );
      if (generation == _mutationGeneration) {
        state = AsyncValue<ShelfSnapshot?>.data(snapshot);
      }
      return snapshot;
    });
    _saveQueue = operation.then((_) {}, onError: (_) {});
    return operation;
  }

  Future<bool> contains(int bookId) async {
    final snapshot = state.valueOrNull;
    if (snapshot != null) {
      return snapshot.items.any((item) => item.isBook && item.bookId == bookId);
    }
    final shelf = await _api.getBookShelf();
    return shelf.items.any((item) => item.isBook && item.bookId == bookId);
  }

  /// 加入/移出书架，返回操作后是否在书架中。
  Future<bool> toggleBook(int bookId) async {
    if (bookId <= 0) throw ArgumentError('无效的书籍 ID。');
    final shelf = await _api.getBookShelf();
    final isInShelf =
        shelf.items.any((item) => item.isBook && item.bookId == bookId);
    final items = isInShelf
        ? shelf.items
            .where((item) => !item.isBook || item.bookId != bookId)
            .toList()
        : <ShelfItem>[
            ShelfItem.book(
              id: bookId,
              index: -1,
              parents: const <String>[],
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
            ...shelf.items,
          ];
    await save(ShelfDraft(items: items, version: shelf.version));
    return !isInShelf;
  }
}

final AsyncNotifierProvider<ShelfController, ShelfSnapshot?> shelfProvider =
    AsyncNotifierProvider<ShelfController, ShelfSnapshot?>(ShelfController.new);
