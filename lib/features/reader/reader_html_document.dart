import 'package:html/dom.dart';

import '../../shared/widgets/html/html_source.dart';

/// 可在脚注抽取和正文分块之间复用的 HTML DOM。
final class ReaderHtmlDocument {
  ReaderHtmlDocument.parse(String html) : fragment = parseRenderableHtml(html);

  final DocumentFragment fragment;

  List<Element> get elements => fragment.querySelectorAll('*');

  String get html => fragment.outerHtml;
}

const Set<String> _visibleVoidTags = <String>{
  'audio',
  'br',
  'hr',
  'iframe',
  'img',
  'svg',
  'video',
};

bool hasRenderableDomContent(Node node) {
  var hasText = false;
  void visit(Node current) {
    if (hasText) return;
    if (current is Text) {
      if (current.data.trim().isNotEmpty) hasText = true;
      return;
    }
    if (current is Element && _visibleVoidTags.contains(current.localName)) {
      hasText = true;
      return;
    }
    for (final child in current.nodes) {
      visit(child);
      if (hasText) return;
    }
  }

  visit(node);
  return hasText;
}
