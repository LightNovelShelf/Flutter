import 'dart:async';

import '../../core/network/request_scheduler.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import 'reader_font_cache.dart';
import 'reader_footnotes.dart';
import 'reader_html_blocks.dart';

/// 小说章节预渲染：取数、分块、摘脚注、装字体一次做完，供阅读器的章节窗口取用。

/// 预渲染好的一章：正文已分块、脚注注文已摘出、章节字体已注册进引擎。
/// 交给阅读视图后只剩排版，没有任何异步等待，翻到相邻章因此不再有加载态。
class ReaderPreparedChapter {
  const ReaderPreparedChapter({
    required this.content,
    required this.blocks,
    required this.notes,
    required this.fontFamily,
  });

  final NovelContent content;
  final List<NovelReaderBlock> blocks;
  final Map<String, String> notes;
  final String? fontFamily;

  NovelChapterContent get chapter => content.chapter;
  int get sortNum => content.chapter.sortNum;
}

class _PrerenderEntry {
  _PrerenderEntry(this.token);

  final CancelToken token;
  late final Future<ReaderPreparedChapter> future;

  /// 只有确实是所请求那一章时才落值：服务端偶尔会回退到别的章节，
  /// 错位的内容不能被当成相邻章塞进翻页条。
  ReaderPreparedChapter? value;
  bool failed = false;
}

/// 章节预渲染：当前章与前后各一章常驻，取数、分块、脚注、字体一次备齐。
///
/// 与旧的「预加载后续 N 章」不同，这里备的是可以直接排版的成品，且向前向后
/// 对称——翻页条要靠它把相邻章接在当前章两端，跨章翻页才没有接缝。
class ReaderChapterPrerenderer {
  ReaderChapterPrerenderer({required ApiClient api, required int bookId})
    : _api = api,
      _bookId = bookId;

  final ApiClient _api;
  final int _bookId;
  final Map<(int, String?), _PrerenderEntry> _entries =
      <(int, String?), _PrerenderEntry>{};

  /// 打开某一章。已备好或在途的结果直接复用；[fresh] 强制重取——按保存的进度
  /// 打开时必须拿到服务端最新的 ReadPosition。
  Future<ReaderPreparedChapter> open({
    required int sortNum,
    required String? convert,
    required bool fresh,
    required bool fontCacheEnabled,
    required int fontCacheLimit,
  }) {
    final key = (sortNum, convert);
    final existing = _entries[key];
    if (!fresh && existing != null && !existing.failed) return existing.future;
    _discard(key);
    return _start(
      key,
      priority: RequestPriority.interactive,
      fontCacheEnabled: fontCacheEnabled,
      fontCacheLimit: fontCacheLimit,
    ).future;
  }

  /// 后台备好某一章并等它就绪。失败、错位或期间被 [retain] 丢弃都返回 null，
  /// 上层据此决定不把它接进翻页条；正式打开时会重新请求。
  Future<ReaderPreparedChapter?> prerender({
    required int sortNum,
    required String? convert,
    required bool fontCacheEnabled,
    required int fontCacheLimit,
  }) async {
    final key = (sortNum, convert);
    final entry =
        _entries[key] ??
        _start(
          key,
          priority: RequestPriority.preload,
          fontCacheEnabled: fontCacheEnabled,
          fontCacheLimit: fontCacheLimit,
        );
    try {
      await entry.future;
    } catch (_) {
      return null;
    }
    return identical(_entries[key], entry) ? entry.value : null;
  }

  /// 只保留这些章，其余连同在途请求一起丢掉。
  void retain(Iterable<int> sortNums, String? convert) {
    final keep = <(int, String?)>{
      for (final sortNum in sortNums) (sortNum, convert),
    };
    for (final key in _entries.keys.toList(growable: false)) {
      if (!keep.contains(key)) _discard(key);
    }
  }

  void dispose() {
    for (final key in _entries.keys.toList(growable: false)) {
      _discard(key);
    }
  }

  void _discard((int, String?) key) => _entries.remove(key)?.token.cancel();

  _PrerenderEntry _start(
    (int, String?) key, {
    required RequestPriority priority,
    required bool fontCacheEnabled,
    required int fontCacheLimit,
  }) {
    final entry = _PrerenderEntry(CancelToken());
    _entries[key] = entry;
    entry.future = _prepare(
      key,
      entry,
      priority: priority,
      fontCacheEnabled: fontCacheEnabled,
      fontCacheLimit: fontCacheLimit,
    );
    // 预渲染没人 await，失败不该冒泡成未捕获异常。
    unawaited(entry.future.then((_) {}, onError: (_) {}));
    return entry;
  }

  Future<ReaderPreparedChapter> _prepare(
    (int, String?) key,
    _PrerenderEntry entry, {
    required RequestPriority priority,
    required bool fontCacheEnabled,
    required int fontCacheLimit,
  }) async {
    try {
      final content = await _api.getNovelContent(
        bookId: _bookId,
        sortNum: key.$1,
        convert: key.$2,
        priority: priority,
        cancelToken: entry.token,
      );
      final fontFamily = await ReaderFontCache.loadFamily(
        content.chapter.fontUrl,
        cacheEnabled: fontCacheEnabled,
        cacheLimit: fontCacheLimit,
      );
      final footnotes = processNovelFootnotes(content.chapter.content);
      // 一个字都不动：分块文本与渲染出来的正文逐字一致，保存的定位才不漂。
      final prepared = ReaderPreparedChapter(
        content: content,
        blocks: normalizeNovelBlocks(footnotes.html),
        notes: footnotes.notesById,
        fontFamily: fontFamily,
      );
      if (content.chapter.bookId == _bookId &&
          content.chapter.sortNum == key.$1) {
        entry.value = prepared;
      }
      return prepared;
    } catch (_) {
      entry.failed = true;
      rethrow;
    }
  }
}
