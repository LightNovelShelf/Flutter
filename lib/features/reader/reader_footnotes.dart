import 'reader_html_text.dart';

/// 脚注抽取：把正文里的脚注标记换成统一锚点，注文摘出来交给底部弹层。
/// 纯字符串变换，与渲染层无关。

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

final RegExp _elementRangePattern = RegExp(
  r'<!--[\s\S]*?-->|</?([a-zA-Z][\w:-]*)\b[^>]*>',
);
final RegExp _footnoteImagePattern = RegExp(
  r'''<img\b[^>]*\bsrc\s*=\s*(?:"[^"]*note\.png(?:[?#][^"]*)?"|'[^']*note\.png(?:[?#][^']*)?'|[^\s>]*note\.png(?:[?#\s>]))''',
  caseSensitive: false,
);
final RegExp _dataLinePattern = RegExp(r'^\d+$');

/// 把脚注标记替换为统一锚点，并把注文从正文中摘出来交给底部弹层。
NovelFootnoteProcessingResult processNovelFootnotes(
  String html, {
  FootnoteMarkerContent markerContent = FootnoteMarkerContent.placeholder,
}) {
  final notesById = <String, String>{};
  final index = _ElementIndex(_parseHtmlElementRanges(html));
  final markers = _selectOutermostFootnoteMarkers(index.elements, html);
  final marker = markerContent == FootnoteMarkerContent.empty ? '' : '*';
  final replacements = <_HtmlReplacement>[];
  final notes = <_HtmlElementRange>[];
  final removedTargets = <String>{};

  for (final element in markers) {
    final id =
        readHtmlAttribute(element.openingTag, 'data-reader-footnote-id') ??
        readHtmlAttribute(element.openingTag, 'data-footnote-id') ??
        _footnoteFragmentId(readHtmlAttribute(element.openingTag, 'href'));
    if (id.isEmpty) continue;

    replacements.add(
      _HtmlReplacement(
        start: element.start,
        end: element.end,
        value:
            '<a data-reader-footnote-id="${escapeHtmlAttribute(id)}">$marker</a>',
      ),
    );

    final note =
        _findFootnoteTarget(index, id) ??
        _findFollowingLegacyFootnoteTarget(index, element, markers);
    if (note == null) continue;
    final key = '${note.start}:${note.end}';
    if (!removedTargets.add(key)) continue;
    notesById[id] = html.substring(note.openingEnd, note.closingStart);
    notes.add(note);
  }

  return NovelFootnoteProcessingResult(
    html: _applyHtmlReplacements(
      html,
      _withNoteRemovals(html, index, notes, replacements),
    ),
    notesById: notesById,
  );
}

/// 注文所在的 `<li>` 摘走后，若父级 `<ol>` 因此变空则一并删除。源站原有的空节点
/// 不处理。
List<_HtmlReplacement> _withNoteRemovals(
  String html,
  _ElementIndex index,
  List<_HtmlElementRange> notes,
  List<_HtmlReplacement> markerReplacements,
) {
  final ordered = List<_HtmlElementRange>.of(notes)
    ..sort((left, right) => left.start.compareTo(right.start));
  // 同一个祖先会被同段落里的每条注文问一遍，而判空要扫完它的整段正文，缓存结果。
  final emptied = <_HtmlElementRange, bool>{};
  bool isEmptied(_HtmlElementRange element) =>
      emptied[element] ??= _isEmptiedBy(html, element, ordered);

  final removals = <String, _HtmlReplacement>{};
  for (final note in ordered) {
    var target = note;
    for (
      var parent = index.enclosing(target);
      parent != null && isEmptied(parent);
      parent = index.enclosing(target)
    ) {
      target = parent;
    }
    removals['${target.start}:${target.end}'] = _HtmlReplacement(
      start: target.start,
      end: target.end,
      value: '',
    );
  }

  // 被整段删除的范围内再做替换会错位，落在其中的标记一并丢弃。
  final coverage = _CoveredRanges(removals.values);
  return <_HtmlReplacement>[
    for (final marker in markerReplacements)
      if (!coverage.covers(marker)) marker,
    for (final removal in removals.values)
      if (!coverage.covers(removal)) removal,
  ];
}

/// 判断一个替换是否被某个更大的删除范围整段盖住。删除范围按 start 升序后，前缀最大
/// end 就够判定，不必两两相比。
class _CoveredRanges {
  _CoveredRanges(Iterable<_HtmlReplacement> removals) {
    final ordered = removals.toList()
      ..sort((left, right) => left.start.compareTo(right.start));
    var maxEnd = -1;
    var minStart = 0;
    for (final removal in ordered) {
      if (removal.end > maxEnd) {
        maxEnd = removal.end;
        // 按 start 升序推进，先达到这个 end 的那个 start 最小。
        minStart = removal.start;
      }
      _starts.add(removal.start);
      _maxEnd.add(maxEnd);
      _minStartAtMaxEnd.add(minStart);
    }
  }

  final List<int> _starts = <int>[];
  final List<int> _maxEnd = <int>[];
  final List<int> _minStartAtMaxEnd = <int>[];

  bool covers(_HtmlReplacement item) {
    final prefix = _countStartsUpTo(item.start);
    if (prefix == 0) return false;
    final maxEnd = _maxEnd[prefix - 1];
    if (maxEnd > item.end) return true;
    // end 相同时只有起点更靠前的才算盖住，范围完全相同的那个就是它自己。
    return maxEnd == item.end && _minStartAtMaxEnd[prefix - 1] < item.start;
  }

  /// start 不大于 [start] 的删除范围个数。
  int _countStartsUpTo(int start) {
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_starts[middle] <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// 包含 [child] 的最小候选元素，[candidates] 已按文档顺序排列。
_HtmlElementRange? _smallestContaining(
  List<_HtmlElementRange> candidates,
  _HtmlElementRange child,
) {
  _HtmlElementRange? best;
  for (final candidate in candidates) {
    if (candidate.start > child.start) break;
    if (candidate.end < child.end) continue;
    if (best == null ||
        candidate.end - candidate.start < best.end - best.start) {
      best = candidate;
    }
  }
  return best;
}

/// 移除 [removals] 覆盖的片段后，[element] 是否还有可渲染内容。
bool _isEmptiedBy(
  String html,
  _HtmlElementRange element,
  List<_HtmlElementRange> removals,
) {
  final buffer = StringBuffer();
  var index = element.openingEnd;
  for (final removal in removals) {
    if (removal.start < index || removal.end > element.closingStart) continue;
    buffer.write(html.substring(index, removal.start));
    index = removal.end;
  }
  buffer.write(html.substring(index, element.closingStart));
  return !hasSomethingToRender(buffer.toString());
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

/// 脚注抽取要反复按 id、标签名和包含关系查元素，每个标记都线性扫一遍元素表会退化成
/// O(n²)。这里的查表结构按需建一次，没有脚注的章节一张也不建。
class _ElementIndex {
  _ElementIndex(this.elements);

  /// 按 start 升序、end 降序排好。
  final List<_HtmlElementRange> elements;

  /// id 与锚点 name 取文档里第一个，与原先的顺序扫描一致。
  late final Map<String, _HtmlElementRange> byId = _collect(
    (element) => readHtmlAttribute(element.openingTag, 'id'),
  );

  late final Map<String, _HtmlElementRange> byAnchorName = _collect(
    (element) => element.tag == 'a'
        ? readHtmlAttribute(element.openingTag, 'name')
        : null,
  );

  late final List<_HtmlElementRange> listItems = <_HtmlElementRange>[
    for (final element in elements)
      if (element.tag == 'li') element,
  ];

  late final List<_HtmlElementRange> lists = <_HtmlElementRange>[
    for (final element in elements)
      if (element.tag == 'ol' || element.tag == 'ul') element,
  ];

  late final int _leaves = _treeLeaves();
  late final List<int> _maxEnd = _buildMaxEndTree();

  /// 最小的严格包含 [child] 的元素。源站 HTML 可以交叉闭合，元素范围不保证真嵌套，
  /// 不能按栈串父子，只能在「start 更小且 end 更大」里取 start 最大的那个。
  _HtmlElementRange? enclosing(_HtmlElementRange child) {
    var index = _rightmostLongerThan(_lowerBound(child.start), child.end);
    if (index < 0) return null;
    // start 相同的一串里取文档靠前那个，也就是 end 最大的。
    while (index > 0 && elements[index - 1].start == elements[index].start) {
      index--;
    }
    return elements[index];
  }

  /// 第一个 start 大于 [start] 的下标。
  int firstStartAfter(int start) => _lowerBound(start + 1);

  Map<String, _HtmlElementRange> _collect(
    String? Function(_HtmlElementRange element) key,
  ) {
    final result = <String, _HtmlElementRange>{};
    for (final element in elements) {
      final value = key(element);
      if (value != null) result.putIfAbsent(value, () => element);
    }
    return result;
  }

  int _lowerBound(int start) {
    var low = 0;
    var high = elements.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (elements[middle].start < start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _treeLeaves() {
    var leaves = 1;
    while (leaves < elements.length) {
      leaves <<= 1;
    }
    return leaves;
  }

  /// end 的区间最大值树，叶子按 elements 下标排列，空位填 -1。
  List<int> _buildMaxEndTree() {
    final tree = List<int>.filled(_leaves * 2, -1);
    for (var index = 0; index < elements.length; index++) {
      tree[_leaves + index] = elements[index].end;
    }
    for (var node = _leaves - 1; node > 0; node--) {
      final left = tree[node * 2];
      final right = tree[node * 2 + 1];
      tree[node] = left > right ? left : right;
    }
    return tree;
  }

  /// 下标小于 [limit] 且 end 大于 [end] 的最大下标，没有就 -1。
  int _rightmostLongerThan(int limit, int end) =>
      limit <= 0 ? -1 : _descend(1, 0, _leaves, limit, end);

  int _descend(int node, int low, int high, int limit, int end) {
    if (low >= limit || _maxEnd[node] <= end) return -1;
    if (high - low == 1) return low;
    final middle = (low + high) >> 1;
    final right = _descend(node * 2 + 1, middle, high, limit, end);
    return right >= 0 ? right : _descend(node * 2, low, middle, limit, end);
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
        readHtmlAttribute(
          element.openingTag,
          'class',
        )?.split(whitespacePattern) ??
        const <String>[];
    if (classes.contains('duokan-footnote')) return true;
    if (element.tag != 'a') return false;
    final href = readHtmlAttribute(element.openingTag, 'href');
    if (href == null || !href.startsWith('#')) return false;
    final inner = html.substring(element.openingEnd, element.closingStart);
    return _footnoteImagePattern.hasMatch(inner);
  }).toList();

  // 嵌套在外层标记内部的标记会被外层整段替换，必须丢弃。
  // 嵌套在外层标记内部的标记会被外层整段替换，必须丢弃。elements 按 start 升序，
  // 更早的标记起点都不更晚，end 没超过此前最大 end 的就是被包住了。
  final outermost = <_HtmlElementRange>[];
  var maxEnd = -1;
  for (final marker in markers) {
    if (maxEnd >= marker.end) continue;
    outermost.add(marker);
    maxEnd = marker.end;
  }
  return outermost;
}

_HtmlElementRange? _findFootnoteTarget(_ElementIndex index, String id) {
  final target = index.byId[id];
  if (target != null) return target;
  final named = index.byAnchorName[id];
  if (named == null) return null;
  // 锚点多半是列表项里的空 `<a name>`，注文取整个 `<li>`。
  return _smallestContaining(index.listItems, named) ?? named;
}

/// 旧书源没有 id 关联：注文是紧跟标记之后、下一个标记之前的 `<li data-line>`。
_HtmlElementRange? _findFollowingLegacyFootnoteTarget(
  _ElementIndex index,
  _HtmlElementRange marker,
  List<_HtmlElementRange> markers,
) {
  final nextMarkerStart = _nextMarkerStart(markers, marker.start);
  final elements = index.elements;
  _HtmlElementRange? candidate;
  for (
    var cursor = index.firstStartAfter(marker.end);
    cursor < elements.length;
    cursor++
  ) {
    final element = elements[cursor];
    if (element.start >= nextMarkerStart) break;
    if (element.tag == 'li' &&
        _dataLinePattern.hasMatch(
          readHtmlAttribute(element.openingTag, 'data-line') ?? '',
        )) {
      candidate = element;
      break;
    }
  }
  if (candidate == null) return null;

  final list = _smallestContaining(index.lists, candidate);
  if (list == null) return candidate;

  // 整个列表只有这一条时连列表一起摘走。
  var items = 0;
  for (final item in index.listItems) {
    if (item.start > list.end) break;
    if (item.start >= list.start && item.end <= list.end) items++;
  }
  return items == 1 ? list : candidate;
}

/// [markers] 按 start 升序，下一个标记的起点；没有下一个时给一个比任何下标都大的值。
int _nextMarkerStart(List<_HtmlElementRange> markers, int start) {
  var low = 0;
  var high = markers.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (markers[middle].start <= start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low == markers.length ? 1 << 62 : markers[low].start;
}

String _applyHtmlReplacements(
  String html,
  List<_HtmlReplacement> replacements,
) {
  // 从后往前替换，否则前面的偏移会失效。
  final ordered = List<_HtmlReplacement>.of(replacements)
    ..sort((left, right) => right.start.compareTo(left.start));
  var output = html;
  for (final replacement in ordered) {
    output = output.replaceRange(
      replacement.start,
      replacement.end,
      replacement.value,
    );
  }
  return output;
}
