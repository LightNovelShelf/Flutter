import 'dart:async';
import 'dart:math' as math;

import '../../data/api/models.dart';
import 'reader_open_position.dart';

/// 阅读器核心逻辑：纯字符串/数据变换，不碰 DOM 与 Flutter，各渲染层共用一套定位语义。

/// 归一化后的最小渲染单元；`locator` 就是服务端保存的阅读进度字符串。
class NovelReaderBlock {
  const NovelReaderBlock({
    required this.id,
    required this.locator,
    required this.html,
    required this.textLength,
    required this.imageCount,
  });

  final String id;
  final String locator;
  final String html;
  final int textLength;
  final int imageCount;
}

class NovelFootnoteProcessingResult {
  const NovelFootnoteProcessingResult({
    required this.html,
    required this.notesById,
  });

  final String html;
  final Map<String, String> notesById;
}

/// 抽出脚注后，正文里保留的标记内容。
enum FootnoteMarkerContent { empty, placeholder }

class ReaderRestorePosition {
  const ReaderRestorePosition({required this.chapterId, required this.position});

  final int chapterId;
  final String position;
}

/// 本地缓存的进度；`isPending` 表示尚未被服务端确认。
class CachedReaderRestorePosition extends ReaderRestorePosition {
  const CachedReaderRestorePosition({
    required super.chapterId,
    required super.position,
    this.isPending = true,
  });

  final bool isPending;
}

class ComicPageSlot {
  const ComicPageSlot({required this.index, required this.image});

  final int index;
  final ComicImage? image;
}

/// 串行化进度写入：慢的旧请求不会覆盖新位置。`schedule` 合并防抖窗口内的多次更新，
/// `commit` 保留切章时的快照顺序。
class ReaderPositionWriteQueue<T> {
  ReaderPositionWriteQueue(
    this._persist, {
    this.delay = const Duration(milliseconds: 450),
    String Function(T value)? fingerprint,
  }) : _fingerprint = fingerprint ?? ((T value) => '$value');

  final FutureOr<void> Function(T value) _persist;

  /// 防抖窗口：窗口内多次上报只写最后一次。
  final Duration delay;
  final String Function(T value) _fingerprint;

  T? _pending;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  String? _lastSuccessfulFingerprint;

  void schedule(T value) {
    _pending = value;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      final value = _pending;
      _pending = null;
      if (value != null) unawaited(_enqueue(value).catchError((Object _) {}));
    });
  }

  Future<void> commit(T value) async {
    _takePending();
    await _enqueue(value).catchError((Object _) {});
  }

  Future<void> flush() async {
    await _takePending()?.catchError((Object _) {});
    await _tail;
  }

  Future<void> dispose() => flush();

  Future<void>? _takePending() {
    _timer?.cancel();
    _timer = null;
    final value = _pending;
    if (value == null) return null;
    _pending = null;
    return _enqueue(value);
  }

  Future<void> _enqueue(T value) {
    final fingerprint = _fingerprint(value);
    final operation = _tail.then((_) async {
      if (fingerprint == _lastSuccessfulFingerprint) return;
      await _persist(value);
      _lastSuccessfulFingerprint = fingerprint;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}

int? getAdjacentChapterSortNum({
  required int sortNum,
  required int totalChapters,
  required bool next,
}) {
  final target = next ? sortNum + 1 : sortNum - 1;
  return target >= 1 && target <= totalChapters ? target : null;
}

int resolveReaderInitialIndex(
  ReaderOpenPosition openPosition,
  int savedIndex,
  int totalItems,
) {
  final lastIndex = math.max(0, totalItems - 1);
  return switch (openPosition) {
    ReaderOpenPosition.start => 0,
    ReaderOpenPosition.end => lastIndex,
    ReaderOpenPosition.saved => math.min(lastIndex, math.max(0, savedIndex)),
  };
}

/// 未同步的本地进度是用户刚刚的操作，优先级最高；已同步的只作兜底，跨设备以服务端为准。
ReaderRestorePosition? resolveReaderRestorePosition(
  int chapterId,
  ReaderRestorePosition? server,
  CachedReaderRestorePosition? cached, {
  bool preferCached = false,
}) {
  final local = cached != null && cached.chapterId == chapterId ? cached : null;
  final remote = server != null && server.chapterId == chapterId ? server : null;
  if (local != null && (local.isPending || preferCached)) return local;
  return remote ?? local;
}

const Set<int> _alwaysInvisibleCodepoints = <int>{
  0x200B,
  0x200C,
  0x200D,
  0xFEFF,
};

final RegExp _textRunPattern = RegExp(r'([^<]+)(?=<|$)');
final RegExp _splitEntityPattern = RegExp('&(?:\u200B*[#A-Za-z0-9xX]+)+\u200B*;');
final RegExp _htmlEntityPattern = RegExp(r'&(#(?:[xX][0-9A-Fa-f]+|[0-9]+)|[A-Za-z]+);');

bool _isInvisibleCodepoint(int codepoint, Set<int> extra) =>
    _alwaysInvisibleCodepoints.contains(codepoint) || extra.contains(codepoint);

int? _decodeNumericHtmlEntity(String token) {
  if (!token.startsWith('#')) return null;
  final hexadecimal = token.length > 1 && (token[1] == 'x' || token[1] == 'X');
  final value = int.tryParse(
    token.substring(hexadecimal ? 2 : 1),
    radix: hexadecimal ? 16 : 10,
  );
  if (value == null) return null;
  return value > 0 && value <= 0x10FFFF ? value : null;
}

/// 只处理文本片段（不碰标签），修复被零宽字符打断的实体并剔除不可见码位。
String sanitizeNovelHtml(
  String html, [
  Set<int> invisibleCodepoints = const <int>{},
]) =>
    html.replaceAllMapped(_textRunPattern, (match) {
      final repaired = match[0]!
          .replaceAllMapped(
            _splitEntityPattern,
            (entity) => entity[0]!.replaceAll('\u200B', ''),
          )
          .replaceAllMapped(_htmlEntityPattern, (entity) {
            final codepoint = _decodeNumericHtmlEntity(entity[1]!);
            return codepoint != null &&
                    _isInvisibleCodepoint(codepoint, invisibleCodepoints)
                ? ''
                : entity[0]!;
          });
      final buffer = StringBuffer();
      for (final codepoint in repaired.runes) {
        if (_isInvisibleCodepoint(codepoint, invisibleCodepoints)) continue;
        buffer.writeCharCode(codepoint);
      }
      return buffer.toString();
    });

final RegExp _pairedMetadataPattern = RegExp(
  r'<(?:base|head|link|meta|noscript|script|style|template|title)\b[^>]*>[\s\S]*?'
  r'</(?:base|head|link|meta|noscript|script|style|template|title)>',
  caseSensitive: false,
);
final RegExp _voidMetadataPattern = RegExp(
  r'<(?:base|link|meta|noscript|script|style|template|title)\b[^>]*/?>',
  caseSensitive: false,
);
final RegExp _hiddenElementPattern = RegExp(
  r'''<([a-zA-Z][\w:-]*)\b[^>]*(?:\bhidden\b|aria-hidden\s*=\s*["']true["']|display\s*:\s*none|visibility\s*:\s*hidden)[^>]*>[\s\S]*?</\1>''',
  caseSensitive: false,
);

String removeReaderMetadata(String html) => html
    .replaceAll(_pairedMetadataPattern, '')
    .replaceAll(_voidMetadataPattern, '')
    .replaceAll(_hiddenElementPattern, '');

const Set<String> _blockTags = <String>{
  'article',
  'blockquote',
  'center',
  'div',
  'figure',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'img',
  'li',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'ul',
};

const Set<String> _leafBlockTags = <String>{
  'p',
  'li',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'img',
};

class _BlockNode {
  _BlockNode({
    required this.tag,
    required this.path,
    required this.start,
    required this.end,
  });

  final String tag;
  final String path;
  final int start;
  int end;
  final List<_BlockNode> children = <_BlockNode>[];
}

final RegExp _blockTagPattern = RegExp(r'<!--[^>]*-->|</?([a-zA-Z][\w:-]*)\b[^>]*>');
final RegExp _imgTagPattern = RegExp(r'<img\b', caseSensitive: false);
final RegExp _anyTagPattern = RegExp(r'<[^>]*>');
final RegExp _imgElementPattern = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final RegExp _nbspPattern = RegExp(r'&nbsp;|&#160;', caseSensitive: false);
final RegExp _whitespacePattern = RegExp(r'\s+');

/// 把服务端 HTML 归一化成稳定的渲染单元。
/// `sanitize: false` 时分块文本与 WebView 的 DOM 逐字一致，定位不漂。
List<NovelReaderBlock> normalizeNovelBlocks(
  String html, {
  Set<int> invisibleCodepoints = const <int>{},
  bool sanitize = true,
}) {
  final source = removeReaderMetadata(
    sanitize ? sanitizeNovelHtml(html, invisibleCodepoints) : html,
  );
  final nodes = _parseHtmlBlockNodes(source);
  final leaves = _selectLeafBlockNodes(nodes, source);
  final blocks = <NovelReaderBlock>[
    for (final node in leaves)
      _createNovelBlock(node.path, source.substring(node.start, node.end)),
  ];
  if (blocks.isNotEmpty) return blocks;

  final fallback = source.trim();
  return fallback.isEmpty
      ? const <NovelReaderBlock>[]
      : <NovelReaderBlock>[_createNovelBlock('//*', fallback)];
}

NovelReaderBlock _createNovelBlock(String locator, String html) {
  final text = html
      .replaceAll(_anyTagPattern, ' ')
      .replaceAll(_nbspPattern, ' ')
      .replaceAll(_whitespacePattern, ' ')
      .trim();
  return NovelReaderBlock(
    id: 'block:$locator',
    locator: locator,
    html: html,
    textLength: text.runes.length,
    imageCount: _imgTagPattern.allMatches(html).length,
  );
}

List<_BlockNode> _parseHtmlBlockNodes(String source) {
  final roots = <_BlockNode>[];
  final stack = <_BlockNode>[];
  for (final match in _blockTagPattern.allMatches(source)) {
    final token = match[0]!;
    final tag = match[1]?.toLowerCase();
    if (tag == null || token.startsWith('<!--') || !_blockTags.contains(tag)) {
      continue;
    }
    if (token.startsWith('</')) {
      var index = -1;
      for (var i = stack.length - 1; i >= 0; i--) {
        if (stack[i].tag == tag) {
          index = i;
          break;
        }
      }
      if (index < 0) continue;
      stack[index].end = match.end;
      stack.removeAt(index);
      continue;
    }
    final parent = stack.isEmpty ? null : stack.last;
    final siblings = parent?.children ?? roots;
    final siblingCount =
        siblings.where((node) => node.tag == tag).length + 1;
    final node = _BlockNode(
      tag: tag,
      path: parent == null
          ? '//*/$tag[$siblingCount]'
          : '${parent.path}/$tag[$siblingCount]',
      start: match.start,
      end: match.end,
    );
    siblings.add(node);
    if (!token.endsWith('/>') && tag != 'img' && tag != 'hr') stack.add(node);
  }
  return roots.where((node) => node.end > node.start).toList();
}

List<_BlockNode> _selectLeafBlockNodes(
  List<_BlockNode> nodes,
  String source,
) {
  final output = <_BlockNode>[];
  void visit(_BlockNode node) {
    final blockChildren =
        node.children.where((child) => _blockTags.contains(child.tag)).toList();
    if (_isStandaloneImageContainer(node, source) ||
        blockChildren.isEmpty ||
        _leafBlockTags.contains(node.tag)) {
      if (source.substring(node.start, node.end).trim().isNotEmpty) {
        output.add(node);
      }
      return;
    }
    blockChildren.forEach(visit);
  }

  nodes.forEach(visit);
  output.sort((left, right) => left.start.compareTo(right.start));
  return output;
}

bool _isStandaloneImageContainer(_BlockNode node, String source) {
  if (node.tag == 'img') return false;
  final html = source.substring(node.start, node.end);
  if (_imgTagPattern.allMatches(html).isEmpty) return false;
  final text = html
      .replaceAll(_imgElementPattern, '')
      .replaceAll(_anyTagPattern, ' ')
      .replaceAll(_nbspPattern, '')
      .replaceAll(_whitespacePattern, '');
  // 纯图片的父节点是作者编排的图组，保留父节点才不丢排版属性与图片顺序。
  return text.isEmpty;
}

final RegExp _locatorHeadPattern = RegExp(r'^/?/?\*?/?');
final RegExp _locatorEdgeSlashPattern = RegExp(r'^/+|/+$');

String cleanReaderLocator(String locator) => locator
    .replaceFirst(_locatorHeadPattern, '')
    .replaceAll(_locatorEdgeSlashPattern, '');

/// 定位失配时逐级回退父路径，旧进度也能落到最近的段落。
int findReaderBlockIndex(List<NovelReaderBlock> blocks, String? locator) {
  if (locator == null || locator.isEmpty) return 0;
  final exact = blocks.indexWhere(
    (block) => block.locator == locator || block.id == locator,
  );
  if (exact >= 0) return exact;

  final indexByLocator = <String, int>{
    for (var index = 0; index < blocks.length; index++)
      cleanReaderLocator(blocks[index].locator): index,
  };
  var candidate = cleanReaderLocator(locator);
  while (candidate.isNotEmpty) {
    final index = indexByLocator[candidate];
    if (index != null) return index;
    final slash = candidate.lastIndexOf('/');
    if (slash < 0) break;
    candidate = candidate.substring(0, slash);
  }
  return 0;
}

class _OpenHtmlElement {
  const _OpenHtmlElement({
    required this.tag,
    required this.start,
    required this.openingEnd,
    required this.openingTag,
  });

  final String tag;
  final int start;
  final int openingEnd;
  final String openingTag;
}

class _HtmlElementRange {
  const _HtmlElementRange({
    required this.tag,
    required this.start,
    required this.openingEnd,
    required this.openingTag,
    required this.closingStart,
    required this.end,
  });

  final String tag;
  final int start;
  final int openingEnd;
  final String openingTag;
  final int closingStart;
  final int end;
}

class _HtmlReplacement {
  const _HtmlReplacement({
    required this.start,
    required this.end,
    required this.value,
  });

  final int start;
  final int end;
  final String value;
}

const Set<String> _voidHtmlTags = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

final RegExp _elementRangePattern =
    RegExp(r'<!--[\s\S]*?-->|</?([a-zA-Z][\w:-]*)\b[^>]*>');
final RegExp _footnoteImagePattern = RegExp(
  r'''<img\b[^>]*\bsrc\s*=\s*(?:"[^"]*note\.png(?:[?#][^"]*)?"|'[^']*note\.png(?:[?#][^']*)?'|[^\s>]*note\.png(?:[?#\s>]))''',
  caseSensitive: false,
);
final RegExp _dataLinePattern = RegExp(r'^\d+$');

String? readHtmlAttribute(String tag, String name) {
  final match = RegExp(
    '\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(tag);
  if (match == null) return null;
  return match[1] ?? match[2] ?? match[3];
}

String escapeHtmlAttribute(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

/// 把脚注标记替换为统一锚点，并把注文从正文中摘出来交给底部弹层。
NovelFootnoteProcessingResult processNovelFootnotes(
  String html, {
  FootnoteMarkerContent markerContent = FootnoteMarkerContent.placeholder,
}) {
  final notesById = <String, String>{};
  final elements = _parseHtmlElementRanges(html);
  final markers = _selectOutermostFootnoteMarkers(elements, html);
  final marker =
      markerContent == FootnoteMarkerContent.empty ? '' : '*';
  final replacements = <_HtmlReplacement>[];
  final removedTargets = <String>{};

  for (final element in markers) {
    final id = readHtmlAttribute(element.openingTag, 'data-reader-footnote-id') ??
        readHtmlAttribute(element.openingTag, 'data-footnote-id') ??
        _footnoteFragmentId(readHtmlAttribute(element.openingTag, 'href'));
    if (id.isEmpty) continue;

    replacements.add(
      _HtmlReplacement(
        start: element.start,
        end: element.end,
        value: '<a data-reader-footnote-id="${escapeHtmlAttribute(id)}">$marker</a>',
      ),
    );

    final note = _findFootnoteTarget(elements, id) ??
        _findFollowingLegacyFootnoteTarget(elements, element, markers);
    if (note == null) continue;
    final key = '${note.start}:${note.end}';
    if (!removedTargets.add(key)) continue;
    notesById[id] = html.substring(note.openingEnd, note.closingStart);
    replacements.add(
      _HtmlReplacement(start: note.start, end: note.end, value: ''),
    );
  }

  return NovelFootnoteProcessingResult(
    html: _applyHtmlReplacements(html, replacements),
    notesById: notesById,
  );
}

String _footnoteFragmentId(String? href) {
  if (href == null || href.isEmpty) return '';
  final hash = href.indexOf('#');
  if (hash < 0 || hash == href.length - 1) return '';
  final fragment = href.substring(hash + 1);
  try {
    return Uri.decodeComponent(fragment);
  } catch (_) {
    return fragment;
  }
}

List<_HtmlElementRange> _parseHtmlElementRanges(String html) {
  final elements = <_HtmlElementRange>[];
  final stack = <_OpenHtmlElement>[];
  for (final match in _elementRangePattern.allMatches(html)) {
    final token = match[0]!;
    final tag = match[1]?.toLowerCase();
    if (tag == null || token.startsWith('<!--')) continue;
    if (token.startsWith('</')) {
      var index = -1;
      for (var i = stack.length - 1; i >= 0; i--) {
        if (stack[i].tag == tag) {
          index = i;
          break;
        }
      }
      if (index < 0) continue;
      final opening = stack.removeAt(index);
      elements.add(
        _HtmlElementRange(
          tag: opening.tag,
          start: opening.start,
          openingEnd: opening.openingEnd,
          openingTag: opening.openingTag,
          closingStart: match.start,
          end: match.end,
        ),
      );
      continue;
    }
    final opening = _OpenHtmlElement(
      tag: tag,
      start: match.start,
      openingEnd: match.end,
      openingTag: token,
    );
    if (token.endsWith('/>') || _voidHtmlTags.contains(tag)) {
      elements.add(
        _HtmlElementRange(
          tag: opening.tag,
          start: opening.start,
          openingEnd: opening.openingEnd,
          openingTag: opening.openingTag,
          closingStart: opening.openingEnd,
          end: opening.openingEnd,
        ),
      );
    } else {
      stack.add(opening);
    }
  }
  elements.sort(
    (left, right) => left.start != right.start
        ? left.start.compareTo(right.start)
        : right.end.compareTo(left.end),
  );
  return elements;
}

List<_HtmlElementRange> _selectOutermostFootnoteMarkers(
  List<_HtmlElementRange> elements,
  String html,
) {
  final markers = elements.where((element) {
    final classes =
        readHtmlAttribute(element.openingTag, 'class')?.split(_whitespacePattern) ??
            const <String>[];
    if (classes.contains('duokan-footnote')) return true;
    if (element.tag != 'a') return false;
    final href = readHtmlAttribute(element.openingTag, 'href');
    if (href == null || !href.startsWith('#')) return false;
    final inner = html.substring(element.openingEnd, element.closingStart);
    return _footnoteImagePattern.hasMatch(inner);
  }).toList();

  // 嵌套在外层标记内部的标记会被外层整段替换，必须丢弃。
  return <_HtmlElementRange>[
    for (var index = 0; index < markers.length; index++)
      if (!markers.take(index).any(
            (other) =>
                other.start <= markers[index].start &&
                other.end >= markers[index].end,
          ))
        markers[index],
  ];
}

_HtmlElementRange? _findFootnoteTarget(
  List<_HtmlElementRange> elements,
  String id,
) {
  for (final element in elements) {
    if (readHtmlAttribute(element.openingTag, 'id') == id) return element;
  }
  _HtmlElementRange? namedTarget;
  for (final element in elements) {
    if (element.tag == 'a' &&
        readHtmlAttribute(element.openingTag, 'name') == id) {
      namedTarget = element;
      break;
    }
  }
  final named = namedTarget;
  if (named == null) return null;

  final containing = elements
      .where(
        (element) =>
            element.tag == 'li' &&
            element.start <= named.start &&
            element.end >= named.end,
      )
      .toList()
    ..sort(
      (left, right) =>
          (left.end - left.start).compareTo(right.end - right.start),
    );
  return containing.isEmpty ? named : containing.first;
}

/// 旧书源没有 id 关联：注文是紧跟标记之后、下一个标记之前的 `<li data-line>`。
_HtmlElementRange? _findFollowingLegacyFootnoteTarget(
  List<_HtmlElementRange> elements,
  _HtmlElementRange marker,
  List<_HtmlElementRange> markers,
) {
  var nextMarkerStart = 1 << 62;
  for (final candidate in markers) {
    if (candidate.start > marker.start && candidate.start < nextMarkerStart) {
      nextMarkerStart = candidate.start;
    }
  }
  _HtmlElementRange? legacyTarget;
  for (final element in elements) {
    if (element.tag == 'li' &&
        element.start > marker.end &&
        element.start < nextMarkerStart &&
        _dataLinePattern
            .hasMatch(readHtmlAttribute(element.openingTag, 'data-line') ?? '')) {
      legacyTarget = element;
      break;
    }
  }
  final candidate = legacyTarget;
  if (candidate == null) return null;

  final lists = elements
      .where(
        (element) =>
            (element.tag == 'ol' || element.tag == 'ul') &&
            element.start <= candidate.start &&
            element.end >= candidate.end,
      )
      .toList()
    ..sort(
      (left, right) =>
          (left.end - left.start).compareTo(right.end - right.start),
    );
  if (lists.isEmpty) return candidate;

  final list = lists.first;
  final items = elements.where(
    (element) =>
        element.tag == 'li' &&
        element.start >= list.start &&
        element.end <= list.end,
  );
  return items.length == 1 ? list : candidate;
}

String _applyHtmlReplacements(
  String html,
  List<_HtmlReplacement> replacements,
) {
  // 从后往前替换，前面的偏移量才不会失效。
  final ordered = List<_HtmlReplacement>.of(replacements)
    ..sort((left, right) => right.start.compareTo(left.start));
  var output = html;
  for (final replacement in ordered) {
    output = output.replaceRange(replacement.start, replacement.end, replacement.value);
  }
  return output;
}

List<ComicPageSlot> createComicPageSlots(int total) => <ComicPageSlot>[
      for (var index = 0; index < math.max(0, total); index++)
        ComicPageSlot(index: index, image: null),
    ];

List<ComicPageSlot> mergeComicPageBatch(
  List<ComicPageSlot> slots,
  int skip,
  List<ComicImage> images,
) {
  final next = List<ComicPageSlot>.of(slots);
  for (var offset = 0; offset < images.length; offset++) {
    final index = skip + offset;
    if (index < 0 || index >= next.length) continue;
    next[index] = ComicPageSlot(index: index, image: images[offset]);
  }
  return next;
}

int getComicPageBatchStart(int index, int total, int batchSize) {
  final clamped = total <= 0 ? 0 : index.clamp(0, total - 1);
  return (clamped ~/ batchSize) * batchSize;
}

/// 边缘 30% 为翻页热区，中间 40% 留给正文交互（切换工具栏）。
int resolveComicTapDirection(double position, double extent) {
  if (extent <= 0) return 0;
  if (position <= extent * 0.3) return -1;
  if (position >= extent * 0.7) return 1;
  return 0;
}

/// 当前页两侧优先，再沿阅读方向多取 4 页。
List<int> createComicPrefetchPlan(int current, int total, int direction) {
  final plan = <int>[];
  void add(int index) {
    if (index < 0 || index >= total || plan.contains(index)) return;
    plan.add(index);
  }

  add(current);
  add(current + 1);
  add(current - 1);
  for (var offset = 0; offset < 4; offset++) {
    add(current + direction * (offset + 2));
  }
  return plan;
}

/// 宽屏/矮屏下限制连续模式正文宽度，免得单页被拉太宽。
double getContinuousComicContentWidth(double width, double height) =>
    height > 0 && width / height > 0.7
        ? math.min(width, height * 0.7)
        : width;
