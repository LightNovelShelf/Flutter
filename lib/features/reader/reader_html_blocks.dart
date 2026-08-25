import 'package:html/dom.dart';

import 'reader_html_document.dart';

/// 归一化后的最小渲染单元；`locator` 就是服务端保存的阅读进度字符串。
class NovelReaderBlock {
  const NovelReaderBlock({required this.locator, required this.html});

  final String locator;
  final String html;
}

/// 移除正文场景不应显示的节点，并输出浏览器规范化后的 HTML。
String removeNonContentHtml(String html) {
  final document = ReaderHtmlDocument.parse(html);
  removeNonContentElements(document);
  return document.html;
}

/// 把服务端 HTML 归一化成稳定的渲染单元。
/// 分块文本必须与渲染出来的正文逐字一致，否则保存的定位会漂。
List<NovelReaderBlock> normalizeNovelBlocks(String html) =>
    normalizeNovelDocument(ReaderHtmlDocument.parse(html));

/// 复用已解析的 DOM 分块，避免脚注处理后再次解析整章。
List<NovelReaderBlock> normalizeNovelDocument(ReaderHtmlDocument document) {
  removeNonContentElements(document);
  final blocks = <NovelReaderBlock>[];
  _visitBlockSiblings(
    nearestReaderBlockChildren(document.fragment),
    parentPath: null,
    onLeaf: (element, path) => blocks.add(_createNovelBlock(path, element)),
  );
  if (blocks.isNotEmpty) return blocks;

  final fallback = document.html.trim();
  return fallback.isEmpty
      ? const <NovelReaderBlock>[]
      : <NovelReaderBlock>[NovelReaderBlock(locator: '//*', html: fallback)];
}

/// 移除正文场景不应显示的 HTML，再按结构拆成可独立排版的块。
///
/// 不做小说专属的脚注转换、定位生成或混淆字体加载。
List<String> splitContentHtmlBlocks(String html) {
  final document = ReaderHtmlDocument.parse(html);
  removeNonContentElements(document);
  final blocks = <String>[];
  _visitBlockSiblings(
    nearestReaderBlockChildren(document.fragment),
    parentPath: null,
    onLeaf: (element, _) => blocks.add(element.outerHtml),
  );
  if (blocks.isNotEmpty) return blocks;
  final fallback = document.html.trim();
  return fallback.isEmpty ? const <String>[] : <String>[fallback];
}

NovelReaderBlock _createNovelBlock(String locator, Element element) =>
    NovelReaderBlock(locator: locator, html: element.outerHtml);

void _visitBlockSiblings(
  List<Element> siblings, {
  required String? parentPath,
  required void Function(Element element, String path) onLeaf,
}) {
  final counts = <String, int>{};
  for (final element in siblings) {
    final tag = element.localName ?? '';
    final index = counts.update(tag, (value) => value + 1, ifAbsent: () => 1);
    final path = parentPath == null
        ? '//*/$tag[$index]'
        : '$parentPath/$tag[$index]';
    final children = nearestReaderBlockChildren(element);
    if (_isStandaloneImageContainer(element) ||
        children.isEmpty ||
        readerLeafBlockTags.contains(tag)) {
      onLeaf(element, path);
    } else {
      _visitBlockSiblings(children, parentPath: path, onLeaf: onLeaf);
    }
  }
}

bool _isStandaloneImageContainer(Element element) =>
    element.localName != 'img' &&
    element.querySelector('img') != null &&
    element.text.trim().isEmpty;
