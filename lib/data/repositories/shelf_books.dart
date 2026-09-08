import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';

class ShelfBookCache {
  ShelfBookCache(this._api);

  final ApiClient _api;
  final _requests = <int, Future<BookListItem?>>{};
  final _pending = <int, Completer<BookListItem?>>{};
  Timer? _timer;

  Future<BookListItem?> load(int id) => _requests.putIfAbsent(id, () {
    final completer = Completer<BookListItem?>();
    _pending[id] = completer;
    // 同一帧构建的卡片共用一次批量请求。
    _timer ??= Timer(Duration.zero, _flush);
    return completer.future;
  });

  Future<void> _flush() async {
    _timer = null;
    final pending = Map<int, Completer<BookListItem?>>.of(_pending);
    _pending.clear();
    try {
      final books = await _api.getBooksByIdsBatched(pending.keys.toList());
      final byId = <int, BookListItem>{for (final book in books) book.id: book};
      for (final entry in pending.entries) {
        entry.value.complete(byId[entry.key]);
      }
    } catch (error, stack) {
      for (final entry in pending.entries) {
        _requests.remove(entry.key);
        entry.value.completeError(error, stack);
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    for (final completer in _pending.values) {
      completer.complete(null);
    }
    _pending.clear();
    _requests.clear();
  }
}

final shelfBookCacheProvider = Provider<ShelfBookCache>((ref) {
  ref.watch(authSnapshotProvider.select((value) => value.isAuthenticated));
  final cache = ShelfBookCache(ref.watch(apiClientProvider));
  ref.onDispose(cache.dispose);
  return cache;
});

final shelfBookProvider = FutureProvider.autoDispose.family<BookListItem?, int>(
  (ref, id) => ref.watch(shelfBookCacheProvider).load(id),
);
