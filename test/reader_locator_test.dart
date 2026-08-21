import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_engine.dart';

/// 服务端存的阅读进度就是一条 xpath（`//*/div[2]/p[76]`），Web 端与客户端必须算出
/// 同一套路径，否则跨端续读会跳段。
const String _html =
    '<div><p>封面</p></div>'
    '<div>'
    '<p>第一段</p>'
    '<p>第二段<a class="duokan-footnote" href="#n1">'
    '<img src="../Images/note.png"/></a></p>'
    '<ol><li id="n1" data-line="2">注文</li></ol>'
    '<p>第三段</p>'
    '</div>';

List<NovelReaderBlock> _blocks(String html) => normalizeNovelBlocks(html);

String _textOf(NovelReaderBlock block) =>
    block.html.replaceAll(RegExp(r'<[^>]*>'), '');

void main() {
  group('阅读进度定位', () {
    test('服务端 xpath 精确命中对应块', () {
      final blocks = _blocks(_html);
      final index = blocks.indexWhere((b) => b.locator == '//*/div[2]/p[3]');

      expect(index, greaterThan(0));
      expect(_textOf(blocks[index]), '第三段');
      expect(findReaderBlockIndex(blocks, '//*/div[2]/p[3]'), index);
    });

    test('摘掉脚注注文不会给同级段落重新编号', () {
      final before = _blocks(_html);
      final after = _blocks(processNovelFootnotes(_html).html);

      // xpath 序号按同名标签计数，删掉 `ol` 里的注文不影响 `p[n]`。
      for (final locator in <String>[
        '//*/div[1]/p[1]',
        '//*/div[2]/p[1]',
        '//*/div[2]/p[2]',
        '//*/div[2]/p[3]',
      ]) {
        final source = before[findReaderBlockIndex(before, locator)];
        final target = after[findReaderBlockIndex(after, locator)];
        expect(target.locator, source.locator, reason: locator);
        // 带脚注标记那段只多了统一锚点，正文本身没动。
        expect(_textOf(target), startsWith(_textOf(source)), reason: locator);
      }

      // 注文连同被它清空的 `<ol>` 一起摘走，正文里不留空壳。
      expect(_textOf(before[3]), '注文');
      expect(before[3].locator, '//*/div[2]/ol[1]/li[1]');
      expect(processNovelFootnotes(_html).html, isNot(contains('<ol')));
      expect(after.any((b) => b.locator.contains('ol')), isFalse);
      expect(after, hasLength(before.length - 1));
    });

    test('源站自带的空节点原样保留，不替它做主', () {
      final blocks = _blocks(
        '<div><p>正文</p><p><br></p><p>&nbsp;</p><div></div><hr></div>',
      );

      expect(blocks.map((b) => b.locator), <String>[
        '//*/div[1]/p[1]',
        '//*/div[1]/p[2]',
        '//*/div[1]/p[3]',
        '//*/div[1]/div[1]',
        '//*/div[1]/hr[1]',
      ]);
    });

    test('同一个 `<ol>` 里两条注文：整段收掉且不重复替换', () {
      const html =
          '<div>'
          '<p>甲<a class="duokan-footnote" href="#n1">'
          '<img src="note.png"/></a>乙'
          '<a class="duokan-footnote" href="#n2"><img src="note.png"/></a></p>'
          '<ol><li id="n1">注一</li><li id="n2">注二</li></ol>'
          '</div>';
      final result = processNovelFootnotes(html);

      expect(result.notesById, <String, String>{'n1': '注一', 'n2': '注二'});
      expect(result.html, isNot(contains('<ol')));
      expect(result.html, isNot(contains('注一')));
      expect(_blocks(result.html).map((b) => b.locator), <String>[
        '//*/div[1]/p[1]',
      ]);
    });

    test('容器里还有别的内容时只摘注文，容器留着', () {
      const html =
          '<div>'
          '<p>甲<a class="duokan-footnote" href="#n1">'
          '<img src="note.png"/></a></p>'
          '<ol><li id="n1">注一</li><li>别的条目</li></ol>'
          '</div>';
      final result = processNovelFootnotes(html);

      expect(result.html, contains('<ol'));
      expect(result.html, contains('别的条目'));
      expect(_blocks(result.html).map((b) => b.locator), <String>[
        '//*/div[1]/p[1]',
        '//*/div[1]/ol[1]/li[1]',
      ]);
    });

    test('路径失配时逐级回退到父级块', () {
      final blocks = _blocks(_html);

      // 父路径自身就是一个块时（旧进度指到段内的行内元素），落回那一段。
      expect(
        findReaderBlockIndex(blocks, '//*/div[2]/p[3]/span[1]'),
        blocks.indexWhere((b) => b.locator == '//*/div[2]/p[3]'),
      );
      // 父路径不是块（`div[2]` 只是容器）时没有可落点，只能回章首。
      expect(findReaderBlockIndex(blocks, '//*/div[2]/p[99]'), 0);
      expect(findReaderBlockIndex(blocks, '//*/section[9]/p[1]'), 0);
    });
  });
}
