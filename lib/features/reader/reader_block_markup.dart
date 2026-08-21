import '../../shared/widgets/html/reader_content_markup.dart';
import '../../shared/widgets/html/reader_content_style.dart';
import 'reader_html_blocks.dart';
import 'reader_html_text.dart';

/// 小说正文块交给渲染器前的最后一道加工：纯字符串变换，方便单测。
///
/// 脚注标记要变成可点的 `[n]` 上标（点击经私有 scheme 回到 Dart）；段首缩进要变成
/// 固定宽度的内联占位，避免普通空白被两端对齐拉伸。

final RegExp _footnoteMarkerPattern = RegExp(
  r'<a\b[^>]*\bdata-reader-footnote-id\s*=\s*"([^"]*)"[^>]*>.*?</a>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _openingTagPattern = RegExp(r'^\s*<([a-zA-Z][\w:-]*)([^>]*)>');

/// 按全章顺序给脚注标记编号，返回与 [blocks] 等长的可渲染 HTML。
List<String> buildReaderBlockMarkup(
  List<NovelReaderBlock> blocks,
  ReaderContentStyle style,
) {
  var footnote = 0;
  return <String>[
    for (final block in blocks)
      _indentBlock(
        block.html.replaceAllMapped(_footnoteMarkerPattern, (match) {
          footnote++;
          final id = _unescapeHtmlAttribute(match[1] ?? '');
          final href = '$readerFootnoteScheme:${Uri.encodeComponent(id)}';
          return '<a href="$href"><sup>[$footnote]</sup></a>';
        }),
        style,
      ),
  ];
}

/// 缩进占位只能插在块内，插到块外会跟着外层对齐方式跑偏。
String _indentBlock(String html, ReaderContentStyle style) {
  final opening = _openingTagPattern.firstMatch(html);
  if (opening == null) return html;
  final classes =
      readHtmlAttribute(
        '<${opening[1]}${opening[2]}>',
        'class',
      )?.split(whitespacePattern) ??
      const <String>[];
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

/// 正文里的 `href` 是转义过的属性值，回到 Dart 前要还原成 `processNovelFootnotes`
/// 交出来的原始 id，否则查不到注文。
String _unescapeHtmlAttribute(String value) =>
    value.replaceAll('&quot;', '"').replaceAll('&amp;', '&');
