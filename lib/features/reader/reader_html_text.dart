/// 正文 HTML 的字符串工具：分块与脚注共用同一套标签与空白判定。
library;

final RegExp anyTagPattern = RegExp(r'<[^>]*>');
final RegExp nbspPattern = RegExp(r'&nbsp;|&#160;', caseSensitive: false);
final RegExp whitespacePattern = RegExp(r'\s+');
final RegExp imgTagPattern = RegExp(r'<img\b', caseSensitive: false);
final RegExp imgElementPattern = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final RegExp visibleVoidTagPattern = RegExp(
  r'<(?:img|br|hr|svg|video|audio|iframe)\b',
  caseSensitive: false,
);

/// 元素是否有可渲染内容。仅用于 `processNovelFootnotes` 判断摘掉注文后祖先是否
/// 变空，源站自带的空节点不受影响。
bool hasSomethingToRender(String html) =>
    visibleVoidTagPattern.hasMatch(html) ||
    html
        .replaceAll(anyTagPattern, ' ')
        .replaceAll(nbspPattern, ' ')
        .replaceAll(whitespacePattern, ' ')
        .trim()
        .isNotEmpty;

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
