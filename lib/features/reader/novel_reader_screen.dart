import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/format.dart';
import '../../shared/widgets/html/reader_content_style.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_chapter_prerenderer.dart';
import 'reader_chapter_window.dart';
import 'reader_open_position.dart';
import 'reader_position.dart';
import 'reader_progress_controller.dart';
import 'reader_providers.dart';
import 'widgets/reader_chapter_sheet.dart';
import 'widgets/reader_chrome.dart';
import 'widgets/reader_content_view.dart';
import 'widgets/reader_footnote_sheet.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/reader_status_pills.dart';

/// 小说阅读器。
///
/// 正文字形被服务端混淆，必须配合章节自带字体渲染：WOFF2 经 libwoff2 转成 TTF 后
/// 注册进 Flutter 引擎，正文由 [ReaderContentView] 渲染。
///
/// 当前章与前后各一章由 [ReaderChapterPrerenderer] 预渲染，三章一起交给正文视图组
/// 成连续的翻页条，跨章翻页把窗口平移一格。
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
  late final ReaderProgressController _progress;
  late final ReaderChapterPrerenderer _prerenderer;

  /// 当前章号；加载中为待打开的章号，加载完成后与窗口当前章一致。
  late int _sortNum;
  late ReaderOpenPosition _openPosition;

  int _requestVersion = 0;
  bool _loading = true;
  String? _error;
  bool _contentReady = false;
  bool _chromeVisible = false;

  /// 当前章与前后各一章，跨章翻页把窗口平移一格。
  ReaderChapterWindow _window = const ReaderChapterWindow.empty();

  int _totalChapters = 0;
  int _currentPage = 0;
  int _totalPages = 0;

  String? _restoreLocator;
  double _restoreProgression = 0;
  int _restoreToken = 0;

  /// 每章最近上报的位置，跨章翻页时用于给离开的章提交进度。
  final Map<int, String> _locators = <int, String>{};
  double _progression = 0;

  @override
  void initState() {
    super.initState();
    _sortNum = widget.sortNum;
    _openPosition = widget.openPosition;
    _api = ref.read(apiClientProvider);
    _progress = ReaderProgressController(api: _api, bookId: widget.bookId);
    _prerenderer = ReaderChapterPrerenderer(api: _api, bookId: widget.bookId);
    unawaited(_load());
  }

  @override
  void dispose() {
    _prerenderer.dispose();
    unawaited(_progress.dispose());
    super.dispose();
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
      final prepared = await _prerenderer.open(
        sortNum: _sortNum,
        convert: convert,
        // 按保存进度打开需要服务端最新的 ReadPosition，不能用预渲染的旧值。
        fresh: _openPosition == ReaderOpenPosition.saved,
        fontCacheEnabled: settings.fontCacheEnabled,
        fontCacheLimit: settings.fontCacheLimit,
      );
      if (!mounted || version != _requestVersion) return;
      final restore = _resolveRestore(prepared, _openPosition);

      setState(() {
        // 服务端可能返回别的章节，以实际返回的章号为准。
        _sortNum = prepared.sortNum;
        _window = ReaderChapterWindow.only(prepared);
        _totalChapters = prepared.chapter.chapterTitles.length;
        _restoreLocator = restore.$1;
        _restoreProgression = restore.$2;
        _restoreToken++;
        _locators[_sortNum] = restore.$1 ?? '';
        _progression = restore.$2;
        _loading = false;
      });
      _syncWindow();
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
    ReaderPreparedChapter prepared,
    ReaderOpenPosition position,
  ) {
    final blocks = prepared.blocks;
    switch (position) {
      case ReaderOpenPosition.start:
        return (blocks.isEmpty ? null : blocks.first.locator, 0.0);
      case ReaderOpenPosition.end:
        return (blocks.isEmpty ? null : blocks.last.locator, 1.0);
      case ReaderOpenPosition.saved:
        final restore = resolveReaderRestore(
          bookId: widget.bookId,
          chapterId: prepared.chapter.id,
          server: prepared.content.readPosition,
        );
        if (restore == null || restore.position.isEmpty) return (null, 0);
        final index = findReaderBlockIndex(blocks, restore.position);
        return (restore.position, blocks.isEmpty ? 0 : index / blocks.length);
    }
  }

  /// 让预渲染窗口跟上当前章，只保留 [_sortNum] 及其前后各一章。
  void _syncWindow() {
    if (_window.isEmpty) return;
    final settings = ref.read(appSettingsProvider);
    final convert = readerConvertParam(settings.convertType);
    if (!settings.readerPrerenderAdjacent) {
      _prerenderer.retain(<int>[_sortNum], convert);
      final alone = _window.alone;
      if (alone != _window) setState(() => _window = alone);
      return;
    }
    final neighbors = _window.neighborSortNums(_totalChapters);
    _prerenderer.retain(<int>[_sortNum, ...neighbors], convert);
    for (final sortNum in neighbors) {
      unawaited(_adopt(sortNum, convert, settings));
    }
  }

  /// 预渲染完成后把相邻章接进窗口，期间窗口移动、繁简变更或关闭预渲染则丢弃结果。
  Future<void> _adopt(
    int sortNum,
    String? convert,
    AppSettings settings,
  ) async {
    final prepared = await _prerenderer.prerender(
      sortNum: sortNum,
      convert: convert,
      fontCacheEnabled: settings.fontCacheEnabled,
      fontCacheLimit: settings.fontCacheLimit,
    );
    if (prepared == null || !mounted) return;
    final current = ref.read(appSettingsProvider);
    if (!current.readerPrerenderAdjacent) return;
    if (readerConvertParam(current.convertType) != convert) return;
    final joined = _window.withNeighbor(prepared);
    if (joined != _window) setState(() => _window = joined);
  }

  String _describe(Object error) {
    if (error is ApiError) return error.message;
    if (error is FormatException) return '章节字体格式无法识别，正文可能显示为乱码。';
    return '章节加载失败，请稍后重试。';
  }

  ReaderContentStyle _contentStyle(
    AppSettings settings,
    Color foreground,
    String? fontFamily,
  ) => ReaderContentStyle(
    fontSize: settings.fontSize,
    lineHeight: settings.readerLineHeight,
    paragraphSpacing: settings.readerParagraphSpacing,
    color: foreground,
    firstLineIndent: settings.readerFirstLineIndent,
    justify: settings.readerJustify,
    fontFamily: fontFamily,
  );

  ReaderChapterContent? _chapterContent(
    ReaderPreparedChapter? prepared,
    AppSettings settings,
    Color foreground,
  ) => prepared == null
      ? null
      : ReaderChapterContent(
          sortNum: prepared.sortNum,
          blocks: prepared.blocks,
          style: _contentStyle(settings, foreground, prepared.fontFamily),
        );

  /// 滚动模式的状态栏留白由外层给出，翻页模式需要计入每一页的内边距。
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
    // 排版与分页参数随 build 生效，只有繁简变更需要重新取正文。
    if (previous == null || _window.isEmpty) return;
    if (previous.convertType != next.convertType) {
      unawaited(_load());
      return;
    }
    if (previous.readerPrerenderAdjacent != next.readerPrerenderAdjacent) {
      _syncWindow();
    }
  }

  void _onPositionReported(ReaderContentPosition position) {
    if (!mounted) return;
    if (position.locator.isNotEmpty) {
      _locators[position.sortNum] = position.locator;
    }
    // 相邻章在切章落定前不是当前章，页码与进度等切换后再更新。
    if (position.sortNum != _sortNum) return;
    _progression = position.progression;
    final pageChanged =
        position.page != _currentPage || position.pages != _totalPages;
    if (pageChanged || _chromeVisible) {
      setState(() {
        _currentPage = position.page;
        _totalPages = position.pages;
      });
    }
    final chapter = _window.current?.chapter;
    if (chapter == null || position.locator.isEmpty) return;
    _progress.stage(chapter.id, position.locator);
  }

  /// 翻页条进入相邻章时把窗口平移一格。
  void _onChapterChanged(int sortNum) {
    final target = _window.at(sortNum);
    if (target == null || sortNum == _sortNum) return;
    final leaving = _window.current;
    final forward = sortNum > _sortNum;
    setState(() {
      _window = _window.moveTo(sortNum);
      _sortNum = sortNum;
      _openPosition = forward
          ? ReaderOpenPosition.start
          : ReaderOpenPosition.end;
      _restoreLocator = _locators[sortNum];
      _restoreProgression = forward ? 0 : 1;
      _progression = forward ? 0 : 1;
    });
    _handoffProgress(leaving, target);
    _syncWindow();
  }

  /// 换章时先提交离开章的进度，再挂上新章的位置。
  void _handoffProgress(
    ReaderPreparedChapter? leaving,
    ReaderPreparedChapter entering,
  ) {
    if (leaving != null && !identical(leaving, entering)) {
      final locator = _locators[leaving.sortNum];
      if (locator != null && locator.isNotEmpty) {
        unawaited(_progress.commit(leaving.chapter.id, locator));
      }
    }
    final locator = _locators[entering.sortNum];
    if (locator != null && locator.isNotEmpty) {
      _progress.stage(entering.chapter.id, locator);
    }
  }

  void _onFootnote(int sortNum, String id) {
    final chapter = _window.at(sortNum);
    final note = chapter?.notes[id];
    if (note == null || note.isEmpty || !mounted) return;
    unawaited(
      showReaderFootnoteSheet(
        context,
        html: note,
        fontFamily: chapter?.fontFamily,
      ),
    );
  }

  Future<void> _openChapter(int sortNum, ReaderOpenPosition position) async {
    if (sortNum < 1 || (_totalChapters > 0 && sortNum > _totalChapters)) return;
    await _commitPosition();
    if (!mounted) return;
    // 已预渲染的章直接切换；按保存进度打开除外，需要服务端最新的 ReadPosition。
    final prepared = position == ReaderOpenPosition.saved
        ? null
        : _window.at(sortNum);
    if (prepared != null) {
      _switchTo(prepared, position);
      return;
    }
    setState(() {
      _sortNum = sortNum;
      _openPosition = position;
    });
    await _load();
  }

  /// 切到窗口内已预渲染的一章，位置定位到 [position]。
  void _switchTo(ReaderPreparedChapter prepared, ReaderOpenPosition position) {
    final restore = _resolveRestore(prepared, position);
    setState(() {
      _openPosition = position;
      // 目标是当前章时窗口不变，只按新的恢复点重新定位。
      _window = _window.moveTo(prepared.sortNum);
      _sortNum = prepared.sortNum;
      _restoreLocator = restore.$1;
      _restoreProgression = restore.$2;
      _restoreToken++;
      _progression = restore.$2;
    });
    final locator = restore.$1;
    if (locator != null && locator.isNotEmpty) {
      _locators[prepared.sortNum] = locator;
    }
    // 离开章的进度已由 [_openChapter] 提交，只需挂上新位置。
    _handoffProgress(null, prepared);
    _syncWindow();
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
    final chapter = _window.current?.chapter;
    final locator = _locators[_sortNum];
    if (chapter == null || locator == null || locator.isEmpty) return;
    await _progress.commit(chapter.id, locator);
  }

  Future<void> _openChapterSheet() async {
    final selection = await showReaderChapterSheet(
      context,
      bookId: widget.bookId,
      currentSortNum: _sortNum,
      comic: false,
      novelChapterTitles:
          _window.current?.chapter.chapterTitles ?? const <String>[],
    );
    if (selection == null) return;
    await _openChapter(selection.sortNum, selection.openPosition);
  }

  String get _title {
    final title = _window.current?.chapter.title ?? '';
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
    final (:background, :foreground) = readerSurfaceColors(context, settings);
    final paged = settings.readerViewMode == ReaderViewMode.paged;
    final readerTopInset = paged ? 0.0 : MediaQuery.paddingOf(context).top;
    final current = _window.current;

    final Widget body;
    if (_error != null) {
      body = Center(
        child: ErrorStateView(
          message: _error!,
          onRetry: () => unawaited(_load()),
        ),
      );
    } else if (_loading || current == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        children: <Widget>[
          Positioned.fill(
            top: readerTopInset,
            child: ReaderContentView(
              chapter: _chapterContent(current, settings, foreground)!,
              previous: _chapterContent(_window.previous, settings, foreground),
              next: _chapterContent(_window.next, settings, foreground),
              paged: paged,
              padding: _contentPadding(settings),
              restoreLocator: _restoreLocator,
              restoreProgression: _restoreProgression,
              restoreToken: _restoreToken,
              onPosition: _onPositionReported,
              onTapCenter: () =>
                  setState(() => _chromeVisible = !_chromeVisible),
              onChapterChanged: _onChapterChanged,
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
