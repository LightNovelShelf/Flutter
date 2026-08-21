import 'reader_html_text.dart';

/// 把服务端 HTML 拆成可独立排版的块：纯字符串变换，不碰 Flutter，
/// 小说阅读器与社区正文共用同一套分块语义。

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

// TODO: 安全解析正文 <style> 并映射到 Flutter 样式；完成前由通用清理统一剥离。
final RegExp _pairedMetadataPattern = RegExp(
  r'<(?:base|head|iframe|link|meta|noscript|object|script|style|template|title)\b[^>]*>[\s\S]*?'
  r'</(?:base|head|iframe|link|meta|noscript|object|script|style|template|title)>',
  caseSensitive: false,
);
final RegExp _voidMetadataPattern = RegExp(
  r'<(?:base|embed|iframe|link|meta|noscript|object|script|style|template|title)\b[^>]*/?>',
  caseSensitive: false,
);
final RegExp _hiddenElementPattern = RegExp(
  r'''<([a-zA-Z][\w:-]*)\b[^>]*(?:\bhidden\b|aria-hidden\s*=\s*["']true["']|display\s*:\s*none|visibility\s*:\s*hidden)[^>]*>[\s\S]*?</\1>''',
  caseSensitive: false,
);

String removeNonContentHtml(String html) => html
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

final RegExp _blockTagPattern = RegExp(
  r'<!--[^>]*-->|</?([a-zA-Z][\w:-]*)\b[^>]*>',
);

/// 把服务端 HTML 归一化成稳定的渲染单元。
/// 不改一个字：分块文本必须与渲染出来的正文逐字一致，否则保存的定位会漂。
List<NovelReaderBlock> normalizeNovelBlocks(String html) {
  final source = removeNonContentHtml(html);
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

/// 清掉所有正文场景都不应显示的 HTML，再按结构拆成可独立排版的块。
///
/// 不执行小说专属的脚注转换、定位生成或混淆字体加载。
List<String> splitContentHtmlBlocks(String html) {
  final source = removeNonContentHtml(html);
  final nodes = _parseHtmlBlockNodes(source);
  final leaves = _selectLeafBlockNodes(nodes, source);
  final blocks = <String>[
    for (final node in leaves) source.substring(node.start, node.end),
  ];
  if (blocks.isNotEmpty) return blocks;
  final fallback = source.trim();
  return fallback.isEmpty ? const <String>[] : <String>[fallback];
}

NovelReaderBlock _createNovelBlock(String locator, String html) {
  final text = html
      .replaceAll(anyTagPattern, ' ')
      .replaceAll(nbspPattern, ' ')
      .replaceAll(whitespacePattern, ' ')
      .trim();

  return NovelReaderBlock(
    id: 'block:$locator',
    locator: locator,
    html: html,
    textLength: text.runes.length,
    imageCount: imgTagPattern.allMatches(html).length,
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
    final siblingCount = siblings.where((node) => node.tag == tag).length + 1;
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

List<_BlockNode> _selectLeafBlockNodes(List<_BlockNode> nodes, String source) {
  final output = <_BlockNode>[];
  void visit(_BlockNode node) {
    final blockChildren = node.children
        .where((child) => _blockTags.contains(child.tag))
        .toList();
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
  if (imgTagPattern.allMatches(html).isEmpty) return false;
  final text = html
      .replaceAll(imgElementPattern, '')
      .replaceAll(anyTagPattern, ' ')
      .replaceAll(nbspPattern, '')
      .replaceAll(whitespacePattern, '');
  // 纯图片的父节点是作者编排的图组，保留父节点才不丢排版属性与图片顺序。
  return text.isEmpty;
}
