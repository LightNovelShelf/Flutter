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
  final elements = _parseHtmlElementRanges(html);
  final markers = _selectOutermostFootnoteMarkers(elements, html);
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
        _findFootnoteTarget(elements, id) ??
        _findFollowingLegacyFootnoteTarget(elements, element, markers);
    if (note == null) continue;
    final key = '${note.start}:${note.end}';
    if (!removedTargets.add(key)) continue;
    notesById[id] = html.substring(note.openingEnd, note.closingStart);
    notes.add(note);
  }

  return NovelFootnoteProcessingResult(
    html: _applyHtmlReplacements(
      html,
      _withNoteRemovals(html, elements, notes, replacements),
    ),
    notesById: notesById,
  );
}

/// 注文所在的 `<li>` 摘走后，若父级 `<ol>` 因此变空则一并删除。源站原有的空节点
/// 不处理。
List<_HtmlReplacement> _withNoteRemovals(
  String html,
  List<_HtmlElementRange> elements,
  List<_HtmlElementRange> notes,
  List<_HtmlReplacement> markerReplacements,
) {
  final ordered = List<_HtmlElementRange>.of(notes)
    ..sort((left, right) => left.start.compareTo(right.start));
  final removals = <String, _HtmlReplacement>{};
  for (final note in ordered) {
    var target = note;
    for (
      var parent = _enclosingElement(elements, target);
      parent != null && _isEmptiedBy(html, parent, ordered);
      parent = _enclosingElement(elements, target)
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
  bool covered(_HtmlReplacement item) => removals.values.any(
    (removal) =>
        removal.start <= item.start &&
        removal.end >= item.end &&
        (removal.start != item.start || removal.end != item.end),
  );

  return <_HtmlReplacement>[
    for (final marker in markerReplacements)
      if (!covered(marker)) marker,
    for (final removal in removals.values)
      if (!covered(removal)) removal,
  ];
}

/// 最小的严格包含 [child] 的元素。
_HtmlElementRange? _enclosingElement(
  List<_HtmlElementRange> elements,
  _HtmlElementRange child,
) {
  _HtmlElementRange? closest;
  for (final element in elements) {
    if (element.start >= child.start || element.end <= child.end) continue;
    if (closest == null || element.start > closest.start) closest = element;
  }
  return closest;
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
  return <_HtmlElementRange>[
    for (var index = 0; index < markers.length; index++)
      if (!markers
          .take(index)
          .any(
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

  final containing =
      elements
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
        _dataLinePattern.hasMatch(
          readHtmlAttribute(element.openingTag, 'data-line') ?? '',
        )) {
      legacyTarget = element;
      break;
    }
  }
  final candidate = legacyTarget;
  if (candidate == null) return null;

  final lists =
      elements
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
