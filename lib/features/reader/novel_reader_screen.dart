import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/read_position_cache.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/format.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_content_style.dart';
import 'reader_engine.dart';
import 'reader_font_cache.dart';
import 'reader_open_position.dart';
import 'reader_providers.dart';
import 'widgets/reader_chapter_sheet.dart';
import 'widgets/reader_chrome.dart';
import 'widgets/reader_content_view.dart';
import 'widgets/reader_footnote_sheet.dart';
import 'widgets/reader_settings_sheet.dart';

/// 小说阅读器。
///
/// 正文字形被服务端混淆过，必须配合章节自带字体才能读：WOFF2 先经 libwoff2 转成
/// TTF，再注册进 Flutter 引擎，正文由 [ReaderContentView] 原生渲染。Dart 侧负责
/// 取数、定位换算与进度保存。
class NovelReaderScreen extends ConsumerStatefulWidget {
  const NovelReaderScreen({
    super.key,
    required this.bookId,
    required this.sortNum,
    this.openPosition = ReaderOpenPosition.saved,
  });

  final int bookId;
  final int sortNum;
  final ReaderOpenPosition openPosition;

  @override
  ConsumerState<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends ConsumerState<NovelReaderScreen> {
  late final ApiClient _api;
  late final ReaderPositionWriteQueue<ReaderRestorePosition> _positions;
  late final AppLifecycleListener _lifecycle;

  late int _sortNum;
  late ReaderOpenPosition _openPosition;

  int _requestVersion = 0;
  bool _loading = true;
  String? _error;
  bool _contentReady = false;
  bool _chromeVisible = false;

  NovelContent? _content;
  List<NovelReaderBlock> _blocks = const <NovelReaderBlock>[];
  Map<String, String> _notes = const <String, String>{};
  String? _fontFamily;
  int _totalChapters = 0;
  int _currentPage = 0;
  int _totalPages = 0;

  String? _restoreLocator;
  double _restoreProgression = 0;
  String _currentLocator = '';
  double _progression = 0;

  @override
  void initState() {
    super.initState();
    _sortNum = widget.sortNum;
    _openPosition = widget.openPosition;
    _api = ref.read(apiClientProvider);
    _positions = ReaderPositionWriteQueue<ReaderRestorePosition>(
      _persistPosition,
      fingerprint: (position) => '${position.chapterId}:${position.position}',
    );
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_positions.flush()),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_positions.dispose());
    super.dispose();
  }

  Future<void> _persistPosition(ReaderRestorePosition position) async {
    try {
      await _api.saveReadPosition(
        bookId: widget.bookId,
        chapterId: position.chapterId,
        position: position.position,
      );
    } catch (_) {
      // 进度写入失败不打断阅读，下一次上报会重试。
    }
  }

  Future<void> _load() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
      _contentReady = false;
      _currentPage = 0;
      _totalPages = 0;
    });

    final settings = ref.read(appSettingsProvider);
    final convert = readerConvertParam(settings.convertType);
    try {
      final cache = ref.read(readerChapterCacheProvider);
      final key = ReaderChapterCacheKey(
        bookId: widget.bookId,
        sortNum: _sortNum,
        convert: convert,
      );
      // 只有翻章打开时才吃预加载：恢复进度必须拿到服务端最新的 ReadPosition。
      final content =
          (_openPosition == ReaderOpenPosition.saved
              ? null
              : cache.take(key)) ??
          await _api.getNovelContent(
            bookId: widget.bookId,
            sortNum: _sortNum,
            convert: convert,
          );
      if (!mounted || version != _requestVersion) return;
      final total = content.chapter.chapterTitles.length;

      final fontFamily = await ReaderFontCache.loadFamily(
        content.chapter.fontUrl,
        cacheEnabled: settings.fontCacheEnabled,
        cacheLimit: settings.fontCacheLimit,
      );
      if (!mounted || version != _requestVersion) {
        return;
      }

      final footnotes = processNovelFootnotes(content.chapter.content);
      // 一个字都不动：分块文本与渲染出来的正文逐字一致，保存的定位才不漂。
      final blocks = normalizeNovelBlocks(footnotes.html);
      final restore = _resolveRestore(content, blocks);

      setState(() {
        _content = content;
        _blocks = blocks;
        _notes = footnotes.notesById;
        _fontFamily = fontFamily;
        _totalChapters = total;
        _restoreLocator = restore.$1;
        _restoreProgression = restore.$2;
        _currentLocator = restore.$1 ?? '';
        _progression = restore.$2;
        _loading = false;
      });
      unawaited(_preload(convert, settings.readerPreloadWindow));
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = _describe(error);
        _loading = false;
      });
    }
  }

  /// 返回 (locator, progression)。
  (String?, double) _resolveRestore(
    NovelContent content,
    List<NovelReaderBlock> blocks,
  ) {
    switch (_openPosition) {
      case ReaderOpenPosition.start:
        return (blocks.isEmpty ? null : blocks.first.locator, 0.0);
      case ReaderOpenPosition.end:
        return (blocks.isEmpty ? null : blocks.last.locator, 1.0);
      case ReaderOpenPosition.saved:
        final cached = ReadPositionCache.read(widget.bookId);
        final server = content.readPosition;
        final restore = resolveReaderRestorePosition(
          content.chapter.id,
          server == null
              ? null
              : ReaderRestorePosition(
                  chapterId: server.chapterId,
                  position: server.position,
                ),
          cached == null
              ? null
              : CachedReaderRestorePosition(
                  chapterId: cached.chapterId,
                  position: cached.position,
                ),
        );
        if (restore == null || restore.position.isEmpty) return (null, 0);
        final index = findReaderBlockIndex(blocks, restore.position);
        return (restore.position, blocks.isEmpty ? 0 : index / blocks.length);
    }
  }

  Future<void> _preload(String? convert, int window) => ref
      .read(readerPreloaderProvider)
      .run(
        bookId: widget.bookId,
        sortNum: _sortNum,
        totalChapters: _totalChapters,
        window: window,
        convert: convert,
      );

  String _describe(Object error) {
    if (error is ApiError) return error.message;
    if (error is FormatException) return '章节字体格式无法识别，正文可能显示为乱码。';
    return '章节加载失败，请稍后重试。';
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color _backgroundColor(AppSettings settings, ColorScheme colors) =>
      _isDark && settings.oledBlack ? Colors.black : colors.surface;

  Color _foregroundColor(AppSettings settings, ColorScheme colors) =>
      _isDark && settings.oledBlack ? Colors.white : colors.onSurface;

  ReaderContentStyle _contentStyle(AppSettings settings) => ReaderContentStyle(
    fontSize: settings.fontSize,
    lineHeight: settings.readerLineHeight,
    paragraphSpacing: settings.readerParagraphSpacing,
    color: _foregroundColor(settings, Theme.of(context).colorScheme),
    firstLineIndent: settings.readerFirstLineIndent,
    justify: settings.readerJustify,
    fontFamily: _fontFamily,
  );

  /// 滚动模式的状态栏留白由外层让位，翻页模式必须落在每一页里。
  EdgeInsets _contentPadding(AppSettings settings) {
    final padding = MediaQuery.paddingOf(context);
    final paged = settings.readerViewMode == ReaderViewMode.paged;
    return EdgeInsets.fromLTRB(
      settings.readerSidePadding,
      (paged ? padding.top : 0) + 12,
      settings.readerSidePadding,
      padding.bottom + (paged ? 56 : 12),
    );
  }

  void _onSettingsChanged(AppSettings? previous, AppSettings next) {
    // 排版、分页方式与图片手势都是 [ReaderContentView] 的入参，随 build 生效；
    // 只有换繁简需要重新取正文。
    if (previous == null || _content == null) return;
    if (previous.convertType != next.convertType) unawaited(_load());
  }

  void _onPositionReported(ReaderContentPosition position) {
    final chapter = _content?.chapter;
    if (chapter == null || !mounted) return;
    if (position.locator.isNotEmpty) _currentLocator = position.locator;
    _progression = position.progression;
    final pageChanged =
        position.page != _currentPage || position.pages != _totalPages;
    if (pageChanged || _chromeVisible) {
      setState(() {
        _currentPage = position.page;
        _totalPages = position.pages;
      });
    }
    if (_currentLocator.isEmpty) return;

    final saved = ReaderRestorePosition(
      chapterId: chapter.id,
      position: _currentLocator,
    );
    // 立刻写进程内缓存，详情页/书架不必等服务端往返就能看到最新章节。
    ReadPositionCache.stage(
      widget.bookId,
      BookReadPosition(
        chapterId: saved.chapterId,
        position: saved.position,
        readAt: DateTime.now(),
      ),
    );
    _positions.schedule(saved);
  }

  void _onFootnote(String id) {
    final note = _notes[id];
    if (note == null || note.isEmpty || !mounted) return;
    unawaited(
      showReaderFootnoteSheet(context, html: note, fontFamily: _fontFamily),
    );
  }

  Future<void> _openChapter(int sortNum, ReaderOpenPosition position) async {
    if (sortNum < 1 || (_totalChapters > 0 && sortNum > _totalChapters)) return;
    await _commitPosition();
    ref.read(readerPreloaderProvider).abort();
    if (!mounted) return;
    setState(() {
      _sortNum = sortNum;
      _openPosition = position;
    });
    await _load();
  }

  Future<void> _openAdjacent(bool next) async {
    final target = getAdjacentChapterSortNum(
      sortNum: _sortNum,
      totalChapters: _totalChapters,
      next: next,
    );
    if (target == null) return;
    await _openChapter(
      target,
      next ? ReaderOpenPosition.start : ReaderOpenPosition.end,
    );
  }

  Future<void> _commitPosition() async {
    final chapter = _content?.chapter;
    if (chapter == null || _currentLocator.isEmpty) return;
    await _positions.commit(
      ReaderRestorePosition(chapterId: chapter.id, position: _currentLocator),
    );
  }

  Future<void> _openChapterSheet() async {
    final selection = await showReaderChapterSheet(
      context,
      bookId: widget.bookId,
      currentSortNum: _sortNum,
      comic: false,
      novelChapterTitles: _content?.chapter.chapterTitles ?? const <String>[],
    );
    if (selection == null) return;
    await _openChapter(selection.sortNum, selection.openPosition);
  }

  String get _title {
    final title = _content?.chapter.title ?? '';
    if (title.isEmpty) return '阅读器';
    final scopes = ref.read(appSettingsProvider).cleanChapterTitleScopes;
    return scopes.contains(CleanChapterTitleScope.readerTitle)
        ? cleanChapterTitle(title)
        : title;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(appSettingsProvider, _onSettingsChanged);
    final settings = ref.watch(appSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    final background = _backgroundColor(settings, colors);
    final foreground = _foregroundColor(settings, colors);
    final paged = settings.readerViewMode == ReaderViewMode.paged;
    final readerTopInset = paged ? 0.0 : MediaQuery.paddingOf(context).top;

    final Widget body;
    if (_error != null) {
      body = Center(
        child: ErrorStateView(
          message: _error!,
          onRetry: () => unawaited(_load()),
        ),
      );
    } else if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        children: <Widget>[
          Positioned.fill(
            top: readerTopInset,
            child: ReaderContentView(
              blocks: _blocks,
              style: _contentStyle(settings),
              paged: paged,
              padding: _contentPadding(settings),
              restoreLocator: _restoreLocator,
              restoreProgression: _restoreProgression,
              onPosition: _onPositionReported,
              onTapCenter: () =>
                  setState(() => _chromeVisible = !_chromeVisible),
              onBoundary: (next) => unawaited(_openAdjacent(next)),
              onFootnote: _onFootnote,
              onReady: () {
                if (mounted && !_contentReady) {
                  setState(() => _contentReady = true);
                }
              },
            ),
          ),
          if (!_contentReady)
            const IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          if (paged && _contentReady && _currentPage > 0 && _totalPages > 0)
            Positioned(
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: ReaderStatusPills(
                visible: !_chromeVisible,
                foregroundColor: foreground,
                currentChapter: _sortNum,
                totalChapters: _totalChapters,
                currentPage: _currentPage,
                totalPages: _totalPages,
              ),
            ),
          ReaderChrome(
            visible: _chromeVisible,
            title: _title,
            backgroundColor: background,
            foregroundColor: foreground,
            currentChapter: _sortNum,
            totalChapters: _totalChapters,
            progress: _progression,
            onOpenChapters: () => unawaited(_openChapterSheet()),
            onOpenSettings: () => unawaited(showReaderSettingsSheet(context)),
            onDismiss: () => setState(() => _chromeVisible = false),
            onPreviousChapter: _sortNum > 1
                ? () => unawaited(_openAdjacent(false))
                : null,
            onNextChapter: _sortNum < _totalChapters
                ? () => unawaited(_openAdjacent(true))
                : null,
          ),
        ],
      ),
    );
  }
}
