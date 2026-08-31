import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';
import 'shelf_draft.dart';

/// 书架错误文案，草稿代数抛出的 [ArgumentError] 消息直接展示给用户。
String describeShelfError(Object error, {String fallback = '书架暂时不可用。'}) {
  if (error is ArgumentError) return error.message?.toString() ?? fallback;
  return describeApiError(
    error,
    fallback: fallback,
    auth: '登录状态已过期，请重新登录后继续。',
    network: '网络连接不可用，请检查后重试。',
    normalize: true,
  );
}

/// 书架仓库：加载、保存（串行队列 + 代际号）与单本增删。
class ShelfController extends AsyncNotifier<ShelfSnapshot?> {
  ApiClient get _api => ref.read(apiClientProvider);

  int _mutationGeneration = 0;
  Future<void> _saveQueue = Future<void>.value();

  @override
  Future<ShelfSnapshot?> build() async {
    // 只看登录与否，token 刷新途中的 refreshing 快照不该把书架拆掉重拉。
    final authenticated = ref.watch(
      authSnapshotProvider.select((snapshot) => snapshot.isAuthenticated),
    );
    if (!authenticated) return null;
    return _load();
  }

  Future<ShelfSnapshot> _hydrate(List<ShelfItem> items, String? version) async {
    final bookIds = items
        .where((item) => item.isBook)
        .map((item) => item.bookId!)
        .toList();
    return ShelfSnapshot(
      items: sortShelfItems(items),
      books: await _api.getBooksByIdsBatched(bookIds),
      version: version,
    );
  }

  Future<ShelfSnapshot> _load() async {
    await _saveQueue;
    final generation = _mutationGeneration;
    final shelf = await _api.getBookShelf();
    final snapshot = await _hydrate(shelf.items, shelf.version);
    if (generation != _mutationGeneration) {
      return state.value ?? snapshot;
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
        for (final book in state.value?.books ?? const <BookListItem>[])
          book.id: book,
      };
      final missingIds = normalized.items
          .where((item) => item.isBook && !knownBooks.containsKey(item.bookId))
          .map((item) => item.bookId!)
          .toList();
      for (final book in await _api.getBooksByIdsBatched(missingIds)) {
        knownBooks[book.id] = book;
      }
      final nextIds = normalized.items
          .where((item) => item.isBook)
          .map((item) => item.bookId!)
          .toSet();
      final snapshot = ShelfSnapshot(
        items: normalized.items,
        books: knownBooks.values
            .where((book) => nextIds.contains(book.id))
            .toList(),
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

  /// 没有缓存快照时回源查询。
  Future<bool> contains(int bookId) async {
    final snapshot = state.value;
    if (snapshot != null) return shelfContainsBook(snapshot.items, bookId);
    final shelf = await _api.getBookShelf();
    return shelfContainsBook(shelf.items, bookId);
  }

  /// 加入/移出书架，返回操作后是否在书架中。
  Future<bool> toggleBook(int bookId) async {
    if (bookId <= 0) throw ArgumentError('无效的书籍 ID。');
    final shelf = await _api.getBookShelf();
    final isInShelf = shelfContainsBook(shelf.items, bookId);
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

  /// 一次把多本书加入根目录；已在书架中的条目保持原位置且不会重复。
  Future<int> addBooks(Iterable<int> bookIds) async {
    final ids = bookIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return 0;
    final shelf = await _api.getBookShelf();
    final existing = shelf.items
        .where((item) => item.isBook)
        .map((item) => item.bookId!)
        .toSet();
    final missing = ids.difference(existing);
    if (missing.isEmpty) return 0;
    final now = DateTime.now().toUtc().toIso8601String();
    await save(
      ShelfDraft(
        items: <ShelfItem>[
          for (final id in missing)
            ShelfItem.book(
              id: id,
              index: -1,
              parents: const <String>[],
              updatedAt: now,
            ),
          ...shelf.items,
        ],
        version: shelf.version,
      ),
    );
    return missing.length;
  }

  /// 一次从书架移出多本书，文件夹和其余条目的位置保持不变。
  Future<int> removeBooks(Iterable<int> bookIds) async {
    final ids = bookIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return 0;
    final shelf = await _api.getBookShelf();
    final removed = shelf.items
        .where((item) => item.isBook && ids.contains(item.bookId))
        .length;
    if (removed == 0) return 0;
    await save(
      ShelfDraft(
        items: shelf.items
            .where((item) => !item.isBook || !ids.contains(item.bookId))
            .toList(),
        version: shelf.version,
      ),
    );
    return removed;
  }
}

final AsyncNotifierProvider<ShelfController, ShelfSnapshot?> shelfProvider =
    AsyncNotifierProvider<ShelfController, ShelfSnapshot?>(ShelfController.new);
