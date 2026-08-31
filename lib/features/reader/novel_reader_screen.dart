import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../core/platform/reader_immersive_mode.dart';
import '../../core/platform/reader_volume_keys.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models/book.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/format.dart';
import '../../shared/widgets/html/reader_content_style.dart';
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
import 'widgets/reader_shell.dart';
import 'widgets/reader_status_pills.dart';
import 'widgets/reader_theme.dart';

/// 窗口保留当前章两侧各几章。双页时一屏最多跨两章，翻过去之前还要备好再往后一章，
/// 留两章足够；更远的章移出窗口，正文块与几何随之释放。
const int _windowRadius = 2;

/// 小说阅读器。
///
/// 正文字形被服务端混淆，必须配合章节自带字体渲染：WOFF2 经 libwoff2 转成 TTF 后
/// 注册进 Flutter 引擎，正文由 [ReaderContentView] 渲染。
///
/// 取回来的章由 [ReaderChapterPrerenderer] 一直缓存到退出阅读器，不会重复请求。
/// 当前章两侧的连续几章组成 [ReaderChapterWindow]，一起交给正文视图接成翻页条；
/// 正文视图翻到条外时按需要一章一章往两端接。
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

class _NovelReaderScreenState extends ConsumerState<NovelReaderScreen>
    with ReaderLoadState<NovelReaderScreen> {
  late final ApiClient _api;
  late final ReaderProgressController _progress;
  late final ReaderChapterPrerenderer _prerenderer;
  final ReaderContentController _contentController = ReaderContentController();

  /// 当前章号；加载中为待打开的章号，加载完成后与窗口当前章一致。
  late int _sortNum;
  late ReaderOpenPosition _openPosition;

  bool _contentReady = false;
  bool _chromeVisible = false;

  /// 当前章与两侧已备好的连续章节，翻页条按它接页。
  ReaderChapterWindow _window = const ReaderChapterWindow.empty();

  /// 取失败的章号，正文视图据此把加载栏换成重试块。
  final Set<int> _failedChapters = <int>{};

  int _totalChapters = 0;

  /// 页码单独走 notifier：翻页只更新右下角的页码胶囊，不重建整个阅读器。
  final ValueNotifier<(int page, int pages)> _pages = ValueNotifier<(int, int)>(
    (0, 0),
  );

  /// 最近一次正文上报，预加载照它取屏首屏尾那两章。
  ReaderContentPosition? _lastPosition;
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
    _prerenderer = ReaderChapterPrerenderer(
      api: _api,
      fonts: ref.read(readerFontRepositoryProvider),
      bookId: widget.bookId,
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _pages.dispose();
    _prerenderer.dispose();
    unawaited(_progress.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final version = beginRequest();
    _pages.value = (0, 0);
    setState(() {
      loading = true;
      loadError = null;
      _contentReady = false;
    });

    final settings = ref.read(appSettingsProvider);
    final convert = readerConvertParam(settings.convertType);
    // 繁简换过之后旧版本的正文不会再用到，别占着缓存。
    _prerenderer.discardExcept(convert);
    try {
      final prepared = await _prerenderer.open(
        sortNum: _sortNum,
        convert: convert,
        // 按保存进度打开需要服务端最新的 ReadPosition，不能用预渲染的旧值。
        fresh: _openPosition == ReaderOpenPosition.saved,
        fontCacheEnabled: settings.fontCacheEnabled,
        fontCacheLimit: settings.fontCacheLimit,
      );
      if (isStale(version)) return;
      final restore = _resolveRestore(prepared, _openPosition);

      setState(() {
        // 服务端可能返回别的章节，以实际返回的章号为准。
        _sortNum = prepared.sortNum;
        _window = ReaderChapterWindow.only(prepared);
        _failedChapters.clear();
        _totalChapters = prepared.chapter.chapterTitles.length;
        _restoreLocator = restore.$1;
        _restoreProgression = restore.$2;
        _restoreToken++;
        _locators[_sortNum] = restore.$1 ?? '';
        _progression = restore.$2;
        loading = false;
      });
      _syncWindow();
    } catch (failure) {
      if (isStale(version)) return;
      setState(() {
        loadError = _describe(failure);
        loading = false;
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
        return (null, 0.0);
      case ReaderOpenPosition.end:
        return (null, 1.0);
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

  /// 让窗口跟上当前章：太远的章移出窗口。
  void _syncWindow() {
    if (_window.isEmpty) return;
    final trimmed = _window.retainAround(_windowRadius);
    if (trimmed != _window) setState(() => _window = trimmed);
    _preload();
  }

  /// 提前备好屏首那一章的上一章、屏尾那一章的下一章。
  ///
  /// 一屏最多跨两章，按屏两端各外扩一章备着，翻一屏之后落在屏首的那一章就一定备好了；
  /// 只有更外面的右栏才可能是加载栏。照当前章两侧备则不够：双页时屏尾常常已经是下一章。
  void _preload() {
    final position = _lastPosition;
    if (position == null || _window.isEmpty) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.readerPrerenderAdjacent) return;
    final convert = readerConvertParam(settings.convertType);
    for (final sortNum in <int>[
      position.sortNum - 1,
      position.tailSortNum + 1,
    ]) {
      if (sortNum < 1) continue;
      if (_totalChapters > 0 && sortNum > _totalChapters) continue;
      if (_window.at(sortNum) != null) continue;
      unawaited(_adopt(sortNum, convert, settings));
    }
  }

  /// 预渲染完成后把相邻章接进窗口，期间窗口挪走、繁简变更或关闭预加载则丢弃结果。
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
    _join(prepared);
  }

  /// 正文视图翻到了翻页条之外：把那一章接进窗口，正文视图在加载栏上等着。
  /// 关掉预加载时这是唯一的取章入口，所以不看 readerPrerenderAdjacent。
  Future<void> _needChapter(bool next, int fromSortNum) async {
    final target = getAdjacentChapterSortNum(
      sortNum: fromSortNum,
      totalChapters: _totalChapters,
      next: next,
    );
    if (target == null || _window.at(target) != null) return;
    final settings = ref.read(appSettingsProvider);
    final convert = readerConvertParam(settings.convertType);
    if (_failedChapters.remove(target)) setState(() {});
    final prepared = await _prerenderer.prerender(
      sortNum: target,
      convert: convert,
      fontCacheEnabled: settings.fontCacheEnabled,
      fontCacheLimit: settings.fontCacheLimit,
      // 用户正盯着加载栏，插到空闲预取前面。
      priority: RequestPriority.interactive,
    );
    if (!mounted) return;
    if (prepared == null) {
      setState(() => _failedChapters.add(target));
      return;
    }
    if (readerConvertParam(ref.read(appSettingsProvider).convertType) !=
        convert) {
      return;
    }
    _join(prepared);
  }

  void _join(ReaderPreparedChapter prepared) {
    final joined = _window.withNeighbor(prepared);
    if (joined != _window) setState(() => _window = joined);
  }

  String _describe(Object error) {
    if (error is ApiError) return error.message;
    if (error is FormatException) return '章节字体格式无法识别，正文可能显示为乱码。';
    return '章节加载失败，请稍后重试。';
  }

  ReaderContentStyle _contentStyle(AppSettings settings, String? fontFamily) =>
      ReaderContentStyle(
        fontSize: settings.fontSize,
        lineHeight: settings.readerLineHeight,
        lineSpace: settings.readerLineSpace,
        firstLineIndent: settings.readerFirstLineIndent,
        justify: settings.readerJustify,
        fontFamily: fontFamily,
      );

  ReaderChapterContent? _chapterContent(
    ReaderPreparedChapter? prepared,
    AppSettings settings,
  ) => prepared == null
      ? null
      : ReaderChapterContent(
          sortNum: prepared.chapter.sortNum,
          blocks: prepared.blocks,
          style: _contentStyle(settings, prepared.fontFamily),
        );

  /// 系统栏由外层 SafeArea 处理，这里只保留正文和页码胶囊的间距。
  EdgeInsets _contentPadding(AppSettings settings) {
    final reader = settings.novelReader;
    final paged = reader.viewMode == ReaderViewMode.paged;
    // 页底那块留白是给页码胶囊的，胶囊关掉就还给正文。
    final pills = paged && reader.statusPillsEnabled;
    return EdgeInsets.fromLTRB(
      settings.readerSidePadding,
      12,
      settings.readerSidePadding,
      pills ? 56 : 12,
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
    _lastPosition = position;
    _progression = position.progression;
    _pages.value = (position.page, position.pages);
    // 工具栏可见时进度条也要跟着走，这时才需要重建整屏。
    if (_chromeVisible) setState(() {});
    _preload();
    final chapter = _window.current?.chapter;
    if (chapter == null || position.locator.isEmpty) return;
    _progress.stage(chapter.id, position.locator);
  }

  /// 翻页条走进了另一章：当前章跟着挪过去，窗口按新的当前章收拢。
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
    final reader = settings.novelReader;
    final (:background, :foreground) = readerSurfaceColors(
      context,
      mode: reader.backgroundMode,
      customColorValue: reader.backgroundColorValue,
      oledBlack: settings.oledBlack,
    );
    final paged = reader.viewMode == ReaderViewMode.paged;
    final current = _window.current;

    final shell = ReaderShell(
      background: background,
      paperTexture: reader.backgroundMode == ReaderBackgroundMode.paper,
      loading: loading || current == null,
      error: loadError,
      onRetry: () => unawaited(_load()),
      body: current == null
          ? const SizedBox.shrink()
          : SafeArea(
              left: false,
              right: false,
              bottom: paged,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    // 正文色走 DefaultTextStyle：亮暗切换只重画文字，不动排版参数，
                    // 也就不会整章重建再分页。
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: foreground),
                      child: ReaderContentView(
                        chapters: <ReaderChapterContent>[
                          for (final prepared in _window.chapters)
                            _chapterContent(prepared, settings)!,
                        ],
                        sortNum: _sortNum,
                        totalChapters: _totalChapters,
                        failedChapters: _failedChapters,
                        paged: paged,
                        pageTurnAnimation: reader.pageTurnAnimation,
                        dualPage: reader.dualPageEnabled,
                        padding: _contentPadding(settings),
                        restoreLocator: _restoreLocator,
                        restoreProgression: _restoreProgression,
                        restoreToken: _restoreToken,
                        onPosition: _onPositionReported,
                        onTapCenter: () =>
                            setState(() => _chromeVisible = !_chromeVisible),
                        onChapterChanged: _onChapterChanged,
                        onBoundary: (next) => unawaited(_openAdjacent(next)),
                        onNeedChapter: (next, from) =>
                            unawaited(_needChapter(next, from)),
                        onFootnote: _onFootnote,
                        onReady: () {
                          if (mounted && !_contentReady) {
                            setState(() => _contentReady = true);
                          }
                        },
                        controller: _contentController,
                      ),
                    ),
                  ),
                  if (!_contentReady)
                    const IgnorePointer(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
      overlay: paged && _contentReady && reader.statusPillsEnabled
          ? Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: ValueListenableBuilder<(int, int)>(
                  valueListenable: _pages,
                  builder: (context, pages, _) {
                    final (page, total) = pages;
                    if (page <= 0 || total <= 0) {
                      return const SizedBox.shrink();
                    }
                    return ReaderStatusPills(
                      visible: !_chromeVisible,
                      foregroundColor: foreground,
                      currentChapter: _sortNum,
                      totalChapters: _totalChapters,
                      currentPage: page,
                      totalPages: total,
                    );
                  },
                ),
              ),
            )
          : null,
      chrome: ReaderChrome(
        visible: _chromeVisible,
        title: _title,
        backgroundColor: background,
        foregroundColor: foreground,
        currentChapter: _sortNum,
        totalChapters: _totalChapters,
        chapterTitles: current?.chapter.chapterTitles ?? const <String>[],
        progress: _progression,
        onOpenChapters: () => unawaited(_openChapterSheet()),
        nightMode: Theme.of(context).brightness == Brightness.dark,
        onToggleNightMode: readerThemeLocked(reader)
            ? null
            : () => toggleReaderNightMode(context, ref, BookType.novel),
        onOpenSettings: () =>
            unawaited(showReaderSettingsSheet(context, BookType.novel)),
        onDismiss: () => setState(() => _chromeVisible = false),
        onPreviousChapter: _sortNum > 1
            ? () => unawaited(_openAdjacent(false))
            : null,
        onNextChapter: _sortNum < _totalChapters
            ? () => unawaited(_openAdjacent(true))
            : null,
        onChapterSelected: (sortNum) =>
            unawaited(_openChapter(sortNum, ReaderOpenPosition.start)),
      ),
    );
    return ReaderImmersiveMode(
      enabled: reader.immersiveEnabled,
      child: ReaderVolumeKeyListener(
        enabled: reader.volumeKeyPagingEnabled && !_chromeVisible,
        onPrevious: _contentController.previousPage,
        onNext: _contentController.nextPage,
        child: shell,
      ),
    );
  }
}
