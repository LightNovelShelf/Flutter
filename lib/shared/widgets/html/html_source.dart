import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

const String htmlImageBlockClass = 'html-image-block';
const String htmlImageSpacingClass = 'html-image-spaced';
const double htmlDefaultBlockSpacing = 8;

sealed class ReaderBlock {
  const ReaderBlock({required this.locator, required this.html});

  final String locator;
  final String html;
}

final class ReaderMarkupBlock extends ReaderBlock {
  const ReaderMarkupBlock({required super.locator, required super.html});
}

final class ReaderImageBlock extends ReaderBlock {
  const ReaderImageBlock({required super.locator, required super.html});
}

const Set<String> htmlBlockTags = <String>{
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

const Set<String> htmlLeafBlockTags = <String>{
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

final RegExp _preprocessCandidate = RegExp(
  r'<\s*(?:article|base|blockquote|center|div|embed|figure|head|iframe|img|link|meta|noscript|object|ol|script|section|style|table|template|title|ul)\b'
  r'|\bhidden\b|\baria-hidden\b|\bstyle\s*=',
  caseSensitive: false,
);

/// 解析渲染源并删除元数据、脚本和显式隐藏节点。
DocumentFragment parseRenderableHtml(String html) {
  final fragment = parseFragment(html);
  removeNonContentElements(fragment);
  applyImageBlockSemantics(fragment);
  return fragment;
}

String prepareRenderableHtml(String html) {
  if (!_preprocessCandidate.hasMatch(html)) return html;
  return parseRenderableHtmlBlocks(html).map((block) => block.html).join();
}

void removeNonContentElements(DocumentFragment root) {
  for (final element in root.querySelectorAll('*').reversed) {
    if (_metadataTags.contains(element.localName) || _isHidden(element)) {
      element.remove();
    }
  }
}

List<Element> nearestHtmlBlockChildren(Node node) {
  final result = <Element>[];
  void visit(Node parent) {
    for (final child in parent.nodes) {
      if (child is! Element) continue;
      if (htmlBlockTags.contains(child.localName)) {
        result.add(child);
      } else {
        visit(child);
      }
    }
  }

  visit(node);
  return result;
}

const Set<String> _imageBlockContainerTags = <String>{
  'center',
  'div',
  'figure',
};

bool isStandaloneImageContainer(Element element) =>
    _imageBlockContainerTags.contains(element.localName) &&
    element.querySelector('img') != null &&
    element.text.trim().isEmpty;

List<Element> _collectRenderableBlockElements(DocumentFragment root) {
  final blocks = <Element>[];
  void collect(List<Element> siblings) {
    for (final element in siblings) {
      final tag = element.localName ?? '';
      final children = nearestHtmlBlockChildren(element);
      if (isStandaloneImageContainer(element) ||
          children.isEmpty ||
          htmlLeafBlockTags.contains(tag)) {
        blocks.add(element);
      } else {
        collect(children);
      }
    }
  }

  collect(nearestHtmlBlockChildren(root));
  return blocks;
}

void applyImageBlockSemantics(DocumentFragment root) {
  final blocks = _collectRenderableBlockElements(root);
  final imagesByBlock = <List<Element>>[
    for (final block in blocks)
      if (block.localName == 'img')
        <Element>[block]
      else if (isStandaloneImageContainer(block))
        block.querySelectorAll('img')
      else
        const <Element>[],
  ];
  for (var blockIndex = 0; blockIndex < imagesByBlock.length; blockIndex++) {
    final images = imagesByBlock[blockIndex];
    for (final image in images) {
      image.classes.add(htmlImageBlockClass);
    }
    if (images.isEmpty) continue;
    blocks[blockIndex].classes.add(htmlImageBlockClass);
    for (var imageIndex = 0; imageIndex + 1 < images.length; imageIndex++) {
      images[imageIndex].classes.add(htmlImageSpacingClass);
    }
    if (blockIndex + 1 < imagesByBlock.length &&
        imagesByBlock[blockIndex + 1].isNotEmpty) {
      images.last.classes.add(htmlImageSpacingClass);
    }
  }
}

List<ReaderBlock> parseRenderableHtmlBlocks(String html) =>
    splitRenderableHtmlBlocks(parseRenderableHtml(html));

List<String> splitContentHtmlBlocks(String html) => <String>[
  for (final block in parseRenderableHtmlBlocks(html)) block.html,
];

List<ReaderBlock> splitRenderableHtmlBlocks(DocumentFragment root) {
  final blocks = <ReaderBlock>[];

  void visit(List<Element> siblings, String? parentPath) {
    final counts = <String, int>{};
    for (final element in siblings) {
      final tag = element.localName ?? '';
      final index = counts.update(tag, (value) => value + 1, ifAbsent: () => 1);
      final path = parentPath == null
          ? '//*/$tag[$index]'
          : '$parentPath/$tag[$index]';
      if (_emitStandaloneImages(element, path, blocks)) continue;
      final children = nearestHtmlBlockChildren(element);
      if (children.isEmpty || htmlLeafBlockTags.contains(tag)) {
        blocks.add(_createReaderBlock(path, element));
      } else {
        visit(children, path);
      }
    }
  }

  visit(nearestHtmlBlockChildren(root), null);
  if (blocks.isNotEmpty) return blocks;
  final fallback = root.outerHtml.trim();
  return fallback.isEmpty
      ? const <ReaderBlock>[]
      : <ReaderBlock>[ReaderMarkupBlock(locator: '//*', html: fallback)];
}

ReaderBlock _createReaderBlock(String locator, Element element) {
  final html = _blockHtml(element);
  return element.querySelector('.$htmlImageBlockClass') != null ||
          element.classes.contains(htmlImageBlockClass)
      ? ReaderImageBlock(locator: locator, html: html)
      : ReaderMarkupBlock(locator: locator, html: html);
}

String _blockHtml(Element element) {
  var rendered = element.clone(true);
  var parent = element.parent;
  while (parent != null && !htmlBlockTags.contains(parent.localName)) {
    final wrapper = parent.clone(false);
    wrapper.append(rendered);
    rendered = wrapper;
    parent = parent.parent;
  }
  return rendered.outerHtml;
}

bool _emitStandaloneImages(
  Element element,
  String path,
  List<ReaderBlock> blocks,
) {
  if (!isStandaloneImageContainer(element)) return false;
  final images = element.querySelectorAll('img');
  if (images.length == 1) {
    blocks.add(_createReaderBlock(path, element));
    return true;
  }
  for (var index = 0; index < images.length; index++) {
    final clone = element.clone(true);
    final clonedImages = clone.querySelectorAll('img');
    for (var other = 0; other < clonedImages.length; other++) {
      if (other != index) clonedImages[other].remove();
    }
    blocks.add(_createReaderBlock('$path/img[${index + 1}]', clone));
  }
  return true;
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
