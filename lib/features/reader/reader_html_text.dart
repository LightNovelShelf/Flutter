/// 正文 HTML 的字符串级公共件：分块与脚注两半都要用同一套标签/空白判定，
/// 各自复制一份就会在「这段还画得出东西吗」上分叉。
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

/// 一个元素是否会画出东西来。源站自带的空节点照留不误，这个判断只服务于
/// `processNovelFootnotes`：摘掉注文之后，要判断包着它的祖先是不是被我们清空了。
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
