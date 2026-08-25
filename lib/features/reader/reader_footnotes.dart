import 'package:html/dom.dart';

import 'reader_html_document.dart';

/// 脚注抽取结果：正文保留统一锚点，注文交给底部弹层。
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

final class _FootnotePlan {
  const _FootnotePlan(this.marker, this.id, this.target);

  final Element marker;
  final String id;
  final Element? target;
}

/// 把脚注标记替换为统一锚点，并把注文从正文中摘出来交给底部弹层。
NovelFootnoteProcessingResult processNovelFootnotes(
  String html, {
  FootnoteMarkerContent markerContent = FootnoteMarkerContent.placeholder,
}) => processNovelFootnotesDocument(
  ReaderHtmlDocument.parse(html),
  markerContent: markerContent,
);

/// 在已解析的 DOM 上抽取脚注，章节预处理可继续复用同一棵树分块。
NovelFootnoteProcessingResult processNovelFootnotesDocument(
  ReaderHtmlDocument document, {
  FootnoteMarkerContent markerContent = FootnoteMarkerContent.placeholder,
}) {
  final elements = document.elements;
  final markers = _outermostFootnoteMarkers(elements);
  final byId = _firstByAttribute(elements, 'id');
  final byAnchorName = _firstByAttribute(
    elements.where((element) => element.localName == 'a'),
    'name',
  );
  final order = <Element, int>{
    for (var index = 0; index < elements.length; index++)
      elements[index]: index,
  };
  final plans = <_FootnotePlan>[];
  for (var markerIndex = 0; markerIndex < markers.length; markerIndex++) {
    final element = markers[markerIndex];
    final id =
        element.attributes['data-reader-footnote-id'] ??
        element.attributes['data-footnote-id'] ??
        _footnoteFragmentId(element.attributes['href']);
    if (id.isEmpty) continue;
    final direct = byId[id];
    final named = byAnchorName[id];
    final target =
        direct ??
        (named == null
            ? null
            : _closestAncestor(named, const <String>{'li'})) ??
        named ??
        _followingLegacyTarget(
          elements,
          order,
          element,
          markerIndex + 1 < markers.length ? markers[markerIndex + 1] : null,
        );
    plans.add(_FootnotePlan(element, id, target));
  }

  final notesById = <String, String>{};
  final removedTargets = Set<Element>.identity();
  final cleanupParents = Set<Element>.identity();
  for (final plan in plans) {
    final target = plan.target;
    if (target == null || !removedTargets.add(target)) continue;
    notesById[plan.id] = target.innerHtml;
    final parent = target.parent;
    if (parent != null) cleanupParents.add(parent);
    target.remove();
  }

  for (final parent in cleanupParents) {
    Element? current = parent;
    while (current != null && !hasRenderableDomContent(current)) {
      final next = current.parent;
      current.remove();
      current = next;
    }
  }

  final markerText = markerContent == FootnoteMarkerContent.empty ? '' : '*';
  for (final plan in plans) {
    if (plan.marker.parentNode == null) continue;
    final replacement = Element.tag('a')
      ..attributes['data-reader-footnote-id'] = plan.id
      ..append(Text(markerText));
    plan.marker.replaceWith(replacement);
  }

  return NovelFootnoteProcessingResult(
    html: document.html,
    notesById: notesById,
  );
}

Map<String, Element> _firstByAttribute(
  Iterable<Element> elements,
  String attribute,
) {
  final result = <String, Element>{};
  for (final element in elements) {
    final value = element.attributes[attribute];
    if (value != null) result.putIfAbsent(value, () => element);
  }
  return result;
}

List<Element> _outermostFootnoteMarkers(List<Element> elements) {
  final candidates = Set<Element>.identity();
  for (final element in elements) {
    if (_isFootnoteMarker(element)) candidates.add(element);
  }
  return <Element>[
    for (final element in elements)
      if (candidates.contains(element) && !_hasAncestorIn(element, candidates))
        element,
  ];
}

bool _isFootnoteMarker(Element element) {
  if (element.classes.contains('duokan-footnote')) return true;
  if (element.localName != 'a' ||
      !(element.attributes['href']?.startsWith('#') ?? false)) {
    return false;
  }
  for (final image in element.querySelectorAll('img')) {
    final source = image.attributes['src'];
    if (source != null && _isFootnoteImage(source)) return true;
  }
  return false;
}

bool _isFootnoteImage(String source) {
  final query = source.indexOf('?');
  final fragment = source.indexOf('#');
  var end = source.length;
  if (query >= 0 && query < end) end = query;
  if (fragment >= 0 && fragment < end) end = fragment;
  return source.substring(0, end).toLowerCase().endsWith('note.png');
}

bool _hasAncestorIn(Element element, Set<Element> candidates) {
  for (var parent = element.parent; parent != null; parent = parent.parent) {
    if (candidates.contains(parent)) return true;
  }
  return false;
}

Element? _closestAncestor(Element element, Set<String> tags) {
  for (Element? current = element; current != null; current = current.parent) {
    if (tags.contains(current.localName)) return current;
  }
  return null;
}

Element? _followingLegacyTarget(
  List<Element> elements,
  Map<Element, int> order,
  Element marker,
  Element? nextMarker,
) {
  final start = (order[marker] ?? -1) + marker.querySelectorAll('*').length + 1;
  final end = nextMarker == null ? elements.length : order[nextMarker]!;
  Element? candidate;
  for (var index = start; index < end; index++) {
    final element = elements[index];
    if (element.localName == 'li' &&
        _containsOnlyDigits(element.attributes['data-line'] ?? '')) {
      candidate = element;
      break;
    }
  }
  if (candidate == null) return null;

  final list = _closestAncestor(candidate, const <String>{'ol', 'ul'});
  if (list == null) return candidate;
  return list.querySelectorAll('li').length == 1 ? list : candidate;
}

bool _containsOnlyDigits(String value) {
  if (value.isEmpty) return false;
  for (final unit in value.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return true;
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
