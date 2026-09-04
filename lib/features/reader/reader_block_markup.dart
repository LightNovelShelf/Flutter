import '../../shared/widgets/html/reader_content_markup.dart';
import '../../shared/widgets/html/reader_content_style.dart';
import '../../shared/widgets/html/html_source.dart';

/// 小说正文块交给渲染器前的字符串加工。
///
/// 脚注标记转成 `[n]` 上标链接（点击经私有 scheme 回到 Dart），段首缩进转成固定
/// 宽度的内联占位，避免普通空白被两端对齐拉伸。

final RegExp _footnoteMarkerPattern = RegExp(
  r'<a data-reader-footnote-id="([^"]*)">.*?</a>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _openingTagPattern = RegExp(
  r'''^\s*<([a-zA-Z][\w:-]*)((?:"[^"]*"|'[^']*'|[^<>'"])*)>''',
);
final RegExp _classAttributePattern = RegExp(
  r'''\bclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  caseSensitive: false,
);
final RegExp _whitespacePattern = RegExp(r'\s+');

/// 按全章首次出现顺序给脚注编号，重复引用复用编号，逐块产出可渲染 HTML。
///
/// 编号状态跨块连续，所以只能顺序取。阅读器按测量分片逐段调用，避免打开章节时
/// 一次性把整章扫完。
class ReaderBlockMarkupBuilder {
  ReaderBlockMarkupBuilder(this.style);

  final ReaderContentStyle style;
  final Map<String, int> _footnoteNumbers = <String, int>{};

  String next(ReaderBlock block) {
    final html = block.html.replaceAllMapped(_footnoteMarkerPattern, (match) {
      final id = _unescapeHtmlAttribute(match[1] ?? '');
      final number = _footnoteNumbers.putIfAbsent(
        id,
        () => _footnoteNumbers.length + 1,
      );
      final href = '$readerFootnoteScheme:${Uri.encodeComponent(id)}';
      return '<a href="$href"><sup>[$number]</sup></a>';
    });
    return _indentBlock(html, style);
  }
}

/// 缩进占位插在块内，插到块外会跟随外层对齐方式偏移。
String _indentBlock(String html, ReaderContentStyle style) {
  final opening = _openingTagPattern.firstMatch(html);
  if (opening == null) return html;
  final classMatch = _classAttributePattern.firstMatch(opening[2] ?? '');
  final classValue = classMatch == null
      ? null
      : classMatch[1] ?? classMatch[2] ?? classMatch[3];
  final classes = classValue?.split(_whitespacePattern) ?? const <String>[];
  if (!style.indentsParagraph(
    tag: opening[1]!.toLowerCase(),
    classes: classes,
  )) {
    return html;
  }
  return '${html.substring(0, opening.end)}'
      '<$readerIndentElement></$readerIndentElement>'
      '${html.substring(opening.end)}';
}

/// href 是转义过的属性值，需还原成 `processNovelFootnotes` 输出的原始 id，否则
/// 查不到注文。
String _unescapeHtmlAttribute(String value) =>
    value.replaceAll('&quot;', '"').replaceAll('&amp;', '&');
