import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

/// 可在脚注抽取和正文分块之间复用的 HTML DOM。
final class ReaderHtmlDocument {
  ReaderHtmlDocument.parse(String html) : fragment = parseFragment(html);

  final DocumentFragment fragment;

  List<Element> get elements => fragment.querySelectorAll('*');

  String get html => fragment.outerHtml;
}

const Set<String> readerBlockTags = <String>{
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

const Set<String> readerLeafBlockTags = <String>{
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

const Set<String> _metadataTags = <String>{
  'base',
  'embed',
  'head',
  'iframe',
  'link',
  'meta',
  'noscript',
  'object',
  'script',
  'style',
  'template',
  'title',
};

const Set<String> _visibleVoidTags = <String>{
  'audio',
  'br',
  'hr',
  'iframe',
  'img',
  'svg',
  'video',
};

/// 删除正文中不应显示的元数据、脚本和显式隐藏节点。
void removeNonContentElements(ReaderHtmlDocument document) {
  for (final element in document.elements.reversed) {
    if (_metadataTags.contains(element.localName) || _isHidden(element)) {
      element.remove();
    }
  }
}

bool _isHidden(Element element) {
  if (element.attributes.containsKey('hidden') ||
      element.attributes['aria-hidden']?.trim().toLowerCase() == 'true') {
    return true;
  }
  final style = element.attributes['style'];
  if (style == null) return false;
  for (final declaration in style.split(';')) {
    final separator = declaration.indexOf(':');
    if (separator < 0) continue;
    final property = declaration.substring(0, separator).trim().toLowerCase();
    final value = declaration.substring(separator + 1).trim().toLowerCase();
    if ((property == 'display' && value == 'none') ||
        (property == 'visibility' && value == 'hidden')) {
      return true;
    }
  }
  return false;
}

/// 深度优先返回最近一层正文块，行内容器不会改变原有定位层级。
List<Element> nearestReaderBlockChildren(Node node) {
  final result = <Element>[];
  void visit(Node parent) {
    for (final child in parent.nodes) {
      if (child is! Element) continue;
      if (readerBlockTags.contains(child.localName)) {
        result.add(child);
      } else {
        visit(child);
      }
    }
  }

  visit(node);
  return result;
}

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
