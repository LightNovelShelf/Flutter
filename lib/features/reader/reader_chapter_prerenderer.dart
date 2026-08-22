import 'dart:async';
import 'dart:isolate';

import '../../core/network/request_scheduler.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/repositories/reader_font_repository.dart';
import 'reader_footnotes.dart';
import 'reader_html_blocks.dart';

/// 小说章节预渲染：取数、分块、脚注抽取、字体注册一次完成，供章节窗口取用。

/// 预渲染好的一章：正文已分块、注文已摘出、章节字体已注册进引擎。
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

  /// 仅在返回的确实是所请求那一章时落值，服务端可能回退到别的章节。
  ReaderPreparedChapter? value;
  bool failed = false;
}

/// 章节预渲染：当前章与前后各一章常驻，取数、分块、脚注、字体一次备齐。
class ReaderChapterPrerenderer {
  ReaderChapterPrerenderer({
    required ApiClient api,
    required ReaderFontRepository fonts,
    required int bookId,
  }) : _api = api,
       _fonts = fonts,
       _bookId = bookId;

  final ApiClient _api;
  final ReaderFontRepository _fonts;
  final int _bookId;
  final Map<(int, String?), _PrerenderEntry> _entries =
      <(int, String?), _PrerenderEntry>{};

  /// 打开某一章，已备好或在途的结果直接复用。[fresh] 强制重取，用于需要服务端
  /// 最新 ReadPosition 的场景。
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

  /// 后台备好某一章并等待就绪。失败、错位或期间被 [retain] 丢弃时返回 null。
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

  /// 只保留这些章，其余连同在途请求一起丢弃。
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
    // 预渲染结果没有 await，异常在此吞掉。
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
      final fontFamily = await _fonts.loadFamily(
        content.chapter.fontUrl,
        cacheEnabled: fontCacheEnabled,
        cacheLimit: fontCacheLimit,
      );
      final markup = await _buildChapterMarkup(content.chapter.content);
      final prepared = ReaderPreparedChapter(
        content: content,
        blocks: markup.blocks,
        notes: markup.notes,
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

/// 脚注抽取与分块的产物，只含字符串与数字，可整体跨 isolate 交回。
class _ChapterMarkup {
  const _ChapterMarkup({required this.blocks, required this.notes});

  final List<NovelReaderBlock> blocks;
  final Map<String, String> notes;
}

/// 短于此长度的正文直接在当前 isolate 算：spawn 与入参拷贝比这点扫描还贵。
const int _isolateMarkupThreshold = 4096;

/// 全章正则扫描加建树，放在 UI isolate 上会在阅读途中掉帧，两步合并进一次 spawn。
Future<_ChapterMarkup> _buildChapterMarkup(String html) =>
    html.length < _isolateMarkupThreshold
    ? Future<_ChapterMarkup>.value(_chapterMarkup(html))
    : Isolate.run(() => _chapterMarkup(html));

_ChapterMarkup _chapterMarkup(String html) {
  final footnotes = processNovelFootnotes(html);
  // 分块文本与渲染出来的正文必须逐字一致，否则保存的定位会漂。
  return _ChapterMarkup(
    blocks: normalizeNovelBlocks(footnotes.html),
    notes: footnotes.notesById,
  );
}
