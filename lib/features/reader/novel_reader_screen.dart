import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/read_position_cache.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/format.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_engine.dart';
import 'reader_font_cache.dart';
import 'reader_html_builder.dart';
import 'reader_open_position.dart';
import 'reader_providers.dart';
import 'widgets/reader_chapter_sheet.dart';
import 'widgets/reader_chrome.dart';
import 'widgets/reader_footnote_sheet.dart';
import 'widgets/reader_settings_sheet.dart';

/// 小说阅读器。
///
/// 正文的字形被服务端混淆过，必须配合章节自带的 WOFF2 才能读；Flutter 无法加载
/// WOFF2，所以正文交给 WebView 的 `@font-face` 渲染，翻页与排版都用 CSS 完成，
/// Dart 侧只负责取数、定位换算与进度保存。
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
  late final WebViewController _controller;
  late final ReaderPositionWriteQueue<ReaderRestorePosition> _positions;
  late final AppLifecycleListener _lifecycle;

  late int _sortNum;
  late ReaderOpenPosition _openPosition;

  int _requestVersion = 0;
  bool _loading = true;
  String? _error;
  bool _documentReady = false;
  bool _chromeVisible = false;

  NovelContent? _content;
  List<NovelReaderBlock> _blocks = const <NovelReaderBlock>[];
  Map<String, String> _notes = const <String, String>{};
  String? _fontDataUrl;
  int _totalChapters = 0;

  String? _restoreLocator;
  double _restoreProgression = 0;
  String _currentLocator = '';
  double _progression = 0;

  ReaderViewMode? _renderedViewMode;

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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        readerBridgeChannel,
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => unawaited(_applyRestore()),
          // 正文里的外链一律不在阅读器内跳转。
          onNavigationRequest: (request) =>
              request.url.startsWith('http://') ||
                      request.url.startsWith('https://')
                  ? NavigationDecision.prevent
                  : NavigationDecision.navigate,
        ),
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
      _documentReady = false;
    });

    final settings = ref.read(appSettingsProvider);
    final convert = readerConvertParam(settings.convertType);
    try {
      // 章节总数只在首次进入时取一次，翻章不必重复拉整本目录。
      final total = _totalChapters > 0
          ? _totalChapters
          : (await ref.read(readerBookDetailProvider(widget.bookId).future))
              .chapters
              .length;
      if (!mounted || version != _requestVersion) return;

      final cache = ref.read(readerChapterCacheProvider);
      final key = ReaderChapterCacheKey(
        bookId: widget.bookId,
        sortNum: _sortNum,
        convert: convert,
      );
      // 只有翻章打开时才吃预加载：恢复进度必须拿到服务端最新的 ReadPosition。
      final content = (_openPosition == ReaderOpenPosition.saved
              ? null
              : cache.take(key)) ??
          await _api.getNovelContent(
            bookId: widget.bookId,
            sortNum: _sortNum,
            convert: convert,
          );
      if (!mounted || version != _requestVersion) return;

      final fontDataUrl = await ReaderFontCache.load(
        content.chapter.fontUrl,
        cacheEnabled: settings.fontCacheEnabled,
        cacheLimit: settings.fontCacheLimit,
      );
      if (!mounted || version != _requestVersion) {
        return;
      }

      final footnotes = processNovelFootnotes(content.chapter.content);
      // sanitize: false —— 分块文本必须与 WebView 里渲染的 DOM 逐字一致，
      // 否则保存的定位会漂移。
      final blocks = normalizeNovelBlocks(footnotes.html, sanitize: false);
      final restore = _resolveRestore(content, blocks);

      setState(() {
        _content = content;
        _blocks = blocks;
        _notes = footnotes.notesById;
        _fontDataUrl = fontDataUrl;
        _totalChapters = total;
        _restoreLocator = restore.$1;
        _restoreProgression = restore.$2;
        _currentLocator = restore.$1 ?? '';
        _progression = restore.$2;
        _loading = false;
      });
      await _renderDocument();
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
        return (
          restore.position,
          blocks.isEmpty ? 0 : index / blocks.length,
        );
    }
  }

  Future<void> _preload(String? convert, int window) =>
      ref.read(readerPreloaderProvider).run(
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

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  ReaderTypography _typography(AppSettings settings) {
    final colors = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    return ReaderTypography(
      backgroundColor: _hex(_backgroundColor(settings, colors)),
      textColor: _hex(_foregroundColor(settings, colors)),
      fontSize: settings.fontSize,
      lineHeight: settings.readerLineHeight,
      sidePadding: settings.readerSidePadding,
      topPadding: padding.top + 12,
      bottomPadding: padding.bottom + 12,
      firstLineIndent: settings.readerFirstLineIndent,
    );
  }

  Future<void> _renderDocument() async {
    final content = _content;
    if (content == null) return;
    final settings = ref.read(appSettingsProvider);
    final paged = settings.readerViewMode == ReaderViewMode.paged;
    _renderedViewMode = settings.readerViewMode;
    if (mounted) setState(() => _documentReady = false);
    final document = buildReaderChapterDocument(
      blocks: _blocks,
      fallbackHtml: content.chapter.content,
      imageBaseUrl: ServiceEndpoints.apiOrigin,
      typography: _typography(settings),
      paged: paged,
      fontDataUrl: _fontDataUrl,
      imagePreviewOnLongPress: settings.readerImagePreviewOpenOnLongPress,
    );
    await _controller.setBackgroundColor(
      _backgroundColor(settings, Theme.of(context).colorScheme),
    );
    await _controller.loadHtmlString(
      document,
      baseUrl: ServiceEndpoints.apiOrigin,
    );
  }

  Future<void> _applyRestore() async {
    await _controller.runJavaScript(
      readerRestoreScript(_restoreLocator, _restoreProgression),
    );
  }

  void _onSettingsChanged(AppSettings? previous, AppSettings next) {
    if (previous == null || _content == null) return;
    if (previous.convertType != next.convertType) {
      unawaited(_load());
      return;
    }
    if (previous.readerViewMode != next.readerViewMode &&
        next.readerViewMode != _renderedViewMode) {
      // 换分页方式要重排文档，先把当前位置钉住再重建。
      _restoreLocator = _currentLocator.isEmpty ? _restoreLocator : _currentLocator;
      _restoreProgression = _progression;
      unawaited(_renderDocument());
      return;
    }
    final typographyChanged = previous.fontSize != next.fontSize ||
        previous.readerLineHeight != next.readerLineHeight ||
        previous.readerSidePadding != next.readerSidePadding ||
        previous.readerFirstLineIndent != next.readerFirstLineIndent ||
        previous.oledBlack != next.oledBlack;
    if (!typographyChanged) return;
    unawaited(
      _controller.runJavaScript(readerTypographyScript(_typography(next))),
    );
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'ready':
        if (mounted) setState(() => _documentReady = true);
      case 'position':
        _onPositionReported(decoded);
      case 'tap':
        _onTap(decoded);
      case 'footnote':
        _onFootnote(decoded['id']);
      case 'image':
        _onImage(decoded['src']);
    }
  }

  void _onPositionReported(Map<String, dynamic> payload) {
    final chapter = _content?.chapter;
    if (chapter == null || !mounted) return;
    final locator = payload['locator'];
    final progression = payload['progression'];
    if (locator is String && locator.isNotEmpty) _currentLocator = locator;
    if (progression is num) _progression = progression.toDouble();
    if (_currentLocator.isEmpty) return;

    final position = ReaderRestorePosition(
      chapterId: chapter.id,
      position: _currentLocator,
    );
    // 立刻写进程内缓存，详情页/书架不必等服务端往返就能看到最新章节。
    ReadPositionCache.stage(
      widget.bookId,
      BookReadPosition(
        chapterId: position.chapterId,
        position: position.position,
        readAt: DateTime.now(),
      ),
    );
    _positions.schedule(position);
    if (_chromeVisible) setState(() {});
  }

  void _onTap(Map<String, dynamic> payload) {
    if (payload['zone'] == 'center') {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }
    if (payload['boundary'] != true) return;
    unawaited(
      payload['zone'] == 'next' ? _openAdjacent(true) : _openAdjacent(false),
    );
  }

  void _onFootnote(Object? id) {
    final note = id is String ? _notes[id] : null;
    if (note == null || note.isEmpty || !mounted) return;
    unawaited(
      showReaderFootnoteSheet(
        context,
        html: note,
        fontDataUrl: _fontDataUrl,
      ),
    );
  }

  void _onImage(Object? source) {
    if (source is! String || source.isEmpty || !mounted) return;
    final resolved = Uri.tryParse(source.replaceAll('&amp;', '&'));
    if (resolved == null) return;
    final url = resolved.hasScheme
        ? resolved.toString()
        : Uri.parse(ServiceEndpoints.apiOrigin).resolveUri(resolved).toString();
    unawaited(showReaderImagePreview(context, url));
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

    final Widget body;
    if (_error != null) {
      body = Center(
        child: ErrorStateView(message: _error!, onRetry: () => unawaited(_load())),
      );
    } else if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        children: <Widget>[
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (!_documentReady)
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
