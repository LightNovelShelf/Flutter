import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_block_markup.dart';
import 'package:lightnovel/features/reader/reader_html_blocks.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_markup.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_style.dart';

ReaderContentStyle _style({bool indent = false}) => ReaderContentStyle(
  fontSize: 18,
  lineHeight: 1.6,
  color: const Color(0xFF000000),
  firstLineIndent: indent,
  justify: false,
);

List<NovelReaderBlock> _blocks(String html) => normalizeNovelBlocks(html);

void main() {
  group('正文标记加工', () {
    test('脚注标记换成带 scheme 的可点上标，编号按全章递增', () {
      final blocks = _blocks(
        '<p>甲<a data-reader-footnote-id="n1">*</a></p>'
        '<p>乙<a data-reader-footnote-id="n2">*</a></p>',
      );
      final builder = ReaderBlockMarkupBuilder(_style());
      final markup = <String>[for (final block in blocks) builder.next(block)];

      expect(markup, hasLength(2));
      expect(markup[0], contains('href="$readerFootnoteScheme:n1"'));
      expect(markup[0], contains('<sup>[1]</sup>'));
      expect(markup[1], contains('href="$readerFootnoteScheme:n2"'));
      expect(markup[1], contains('<sup>[2]</sup>'));
      expect(markup.join(), isNot(contains('data-reader-footnote-id')));
    });

    test('转义过的 id 还原成 processNovelFootnotes 交出的原值', () {
      final block = _blocks(
        '<p>甲<a data-reader-footnote-id="a&amp;b">*</a></p>',
      ).single;
      final markup = ReaderBlockMarkupBuilder(_style()).next(block);
      final href = RegExp(r'href="([^"]+)"').firstMatch(markup)?[1];

      expect(href, isNotNull);
      expect(readerFootnoteIdFromUrl(href!), 'a&b');
    });

    test('非脚注链接不认这个 scheme', () {
      expect(readerFootnoteIdFromUrl('https://example.com/a'), isNull);
      expect(readerFootnoteIdFromUrl('#anchor'), isNull);
      expect(readerFootnoteIdFromUrl('$readerFootnoteScheme:'), isNull);
    });

    test('段首缩进插在块内，且只插在会缩进的段落上', () {
      final blocks = _blocks('<p>正文</p><p class="center">居中</p><h2>标题</h2>');
      final offBuilder = ReaderBlockMarkupBuilder(_style());
      final onBuilder = ReaderBlockMarkupBuilder(_style(indent: true));
      final off = <String>[for (final block in blocks) offBuilder.next(block)];
      final on = <String>[for (final block in blocks) onBuilder.next(block)];

      expect(off.every((html) => !html.contains(readerIndentElement)), isTrue);
      expect(on[0], '<p><$readerIndentElement></$readerIndentElement>正文</p>');
      expect(on[1], isNot(contains(readerIndentElement)));
      expect(on[2], isNot(contains(readerIndentElement)));
    });
  });

  test('通用 HTML 分块清理非正文节点，但不执行小说标记加工', () {
    const html =
        '<head><title>隐藏标题</title></head>'
        '<style>p { color: red; }</style>'
        '<p data-reader-footnote-id="keep">甲</p>'
        '<iframe src="https://example.com/frame">框架内容</iframe>'
        '<embed src="https://example.com/media">'
        '<div hidden>隐藏正文</div>'
        '<div class="community">乙</div>'
        '<object data="movie.bin"><param name="quality" value="high">备用内容</object>';
    expect(splitContentHtmlBlocks(html), <String>[
      '<p data-reader-footnote-id="keep">甲</p>',
      '<div class="community">乙</div>',
    ]);
  });
}
