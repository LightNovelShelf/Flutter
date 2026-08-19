import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';

String? readerConvertParam(ConvertType type) =>
    type == ConvertType.none ? null : type.name;

/// 章节目录：阅读器与目录弹层共用一份数据。
final AutoDisposeFutureProviderFamily<BookDetail, int> readerBookDetailProvider =
    FutureProvider.autoDispose.family<BookDetail, int>(
  (ref, bookId) => ref.watch(apiClientProvider).getBookInfo(bookId),
);

final AutoDisposeFutureProviderFamily<ComicInfo, int> readerComicInfoProvider =
    FutureProvider.autoDispose.family<ComicInfo, int>(
  (ref, bookId) => ref.watch(apiClientProvider).getComicInfo(bookId),
);

class ReaderChapterCacheKey {
  const ReaderChapterCacheKey({
    required this.bookId,
    required this.sortNum,
    required this.convert,
  });

  final int bookId;
  final int sortNum;
  final String? convert;

  @override
  bool operator ==(Object other) =>
      other is ReaderChapterCacheKey &&
      other.bookId == bookId &&
      other.sortNum == sortNum &&
      other.convert == convert;

  @override
  int get hashCode => Object.hash(bookId, sortNum, convert);
}

/// 预加载缓存：命中即消费，正式加载永不等预加载。
class ReaderChapterCache {
  static const int _capacity = 6;

  final Map<ReaderChapterCacheKey, NovelContent> _entries =
      <ReaderChapterCacheKey, NovelContent>{};

  void put(ReaderChapterCacheKey key, NovelContent content) {
    _entries.remove(key);
    _entries[key] = content;
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  NovelContent? take(ReaderChapterCacheKey key) => _entries.remove(key);

  void clearBook(int bookId) =>
      _entries.removeWhere((key, _) => key.bookId == bookId);
}

final Provider<ReaderChapterCache> readerChapterCacheProvider =
    Provider<ReaderChapterCache>((ref) => ReaderChapterCache());

/// 只向后预加载，逐个发起，切章/退出立刻放弃未开始的请求。
class ReaderChapterPreloader {
  ReaderChapterPreloader(this._api, this._cache);

  static const int _maxWindow = 3;

  final ApiClient _api;
  final ReaderChapterCache _cache;
  CancelToken? _token;

  void abort() {
    _token?.cancel();
    _token = null;
  }

  Future<void> run({
    required int bookId,
    required int sortNum,
    required int totalChapters,
    required int window,
    required String? convert,
  }) async {
    abort();
    final count = <int>[
      _maxWindow,
      window,
      totalChapters - sortNum,
    ].reduce((a, b) => a < b ? a : b);
    if (count <= 0) return;

    final token = CancelToken();
    _token = token;
    for (var offset = 1; offset <= count; offset++) {
      if (token.isCancelled) return;
      final target = sortNum + offset;
      final key = ReaderChapterCacheKey(
        bookId: bookId,
        sortNum: target,
        convert: convert,
      );
      try {
        final content = await _api.getNovelContent(
          bookId: bookId,
          sortNum: target,
          convert: convert,
          priority: RequestPriority.preload,
          cancelToken: token,
        );
        if (token.isCancelled) return;
        // 服务端偶尔会回退到别的章节，错位的内容不能进缓存。
        if (content.chapter.bookId != bookId ||
            content.chapter.sortNum != target) {
          continue;
        }
        _cache.put(key, content);
      } on RequestCancelledError {
        return;
      } catch (_) {
        // 预加载失败无声忽略，正式打开时会重新请求。
      }
    }
  }
}

final Provider<ReaderChapterPreloader> readerPreloaderProvider =
    Provider<ReaderChapterPreloader>((ref) {
  final preloader = ReaderChapterPreloader(
    ref.watch(apiClientProvider),
    ref.watch(readerChapterCacheProvider),
  );
  ref.onDispose(preloader.abort);
  return preloader;
});
