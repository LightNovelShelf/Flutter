import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_style.dart';

const _style = ReaderContentStyle(
  fontSize: 18,
  lineHeight: 1.6,
  color: Color(0xFF222222),
  firstLineIndent: true,
  justify: false,
);

Map<String, String>? _styles({
  String? tag,
  Iterable<String> classes = const <String>[],
  Map<String, String> attributes = const <String, String>{},
  ReaderContentStyle style = _style,
}) => style.stylesFor(tag: tag, classes: classes, attributes: attributes);

void main() {
  test('textStyle 直接反映正文设置', () {
    const styled = ReaderContentStyle(
      fontSize: 20,
      lineHeight: 1.8,
      color: Color(0xFF112233),
      firstLineIndent: false,
      justify: false,
      fontFamily: 'ln-obf-1',
    );
    expect(
      styled.textStyle,
      const TextStyle(
        fontSize: 20,
        height: 1.8,
        color: Color(0xFF112233),
        fontFamily: 'ln-obf-1',
      ),
    );
  });

  test('段间距不改变单行文字行高或 HTML 默认边距', () {
    const spaced = ReaderContentStyle(
      fontSize: 16,
      lineHeight: 1.5,
      paragraphSpacing: 4,
      color: Color(0xFF222222),
      firstLineIndent: false,
      justify: false,
    );
    expect(spaced.textStyle.height, 1.5);
    expect(_styles(tag: 'p', style: spaced), <String, String>{'margin': '0'});
  });

  test('段首缩进由 indentsParagraph 判定，不再吐 text-indent', () {
    const noIndent = ReaderContentStyle(
      fontSize: 18,
      lineHeight: 1.6,
      color: Color(0xFF222222),
      firstLineIndent: false,
      justify: false,
    );
    expect(_styles(tag: 'p'), <String, String>{'margin': '0'});
    expect(_style.indentsParagraph(tag: 'p', classes: const []), isTrue);
    expect(
      _style.indentsParagraph(tag: 'p', classes: const ['center']),
      isFalse,
    );
    for (final className in const ['pius1', 'pius2', 'ph4']) {
      expect(_style.indentsParagraph(tag: 'p', classes: [className]), isFalse);
    }
    expect(_style.indentsParagraph(tag: 'div', classes: const []), isFalse);
    expect(noIndent.indentsParagraph(tag: 'p', classes: const []), isFalse);
  });

  test('输出里没有 HtmlWidget 不解析的死声明', () {
    const tags = <String?>[
      null,
      'p',
      'h1',
      'h2',
      'h3',
      'h4',
      'a',
      'img',
      'table',
      'th',
      'td',
      'rt',
      'font',
      'div',
    ];
    const classNames = <String>[
      'right',
      'left',
      'center',
      'zin',
      'bold',
      'ita',
      'stress',
      'author',
      'message',
      'cut-line',
      'meg',
      'lh',
      'm0',
      'p0',
      'dash-break',
      'no-d',
      'red',
      'green',
      'blue',
      'black',
      'white',
      'dot',
      'em-dot',
      'pius1',
      'pius2',
      'ph4',
      'illu',
      'illus',
      'duokan-image-single',
      'em13',
    ];
    const dead = <String>{
      'text-indent',
      'text-emphasis-position',
      'word-break',
    };
    for (final tag in tags) {
      for (final className in classNames) {
        final keys =
            _styles(
              tag: tag,
              classes: [className],
              attributes: const {'size': '3'},
            )?.keys ??
            const <String>[];
        expect(
          keys.where(dead.contains),
          isEmpty,
          reason: '$tag.$className 吐出了死声明',
        );
      }
    }
  });

  test('em13 相对字号按基准字号缩放', () {
    expect(_styles(classes: const ['em13'])?['font-size'], '23.40px');
    expect(
      _styles(
        classes: const ['em13'],
        style: const ReaderContentStyle(
          fontSize: 24,
          lineHeight: 1.6,
          color: Color(0xFF222222),
          firstLineIndent: true,
          justify: false,
        ),
      )?['font-size'],
      '31.20px',
    );

    // em10 是空档，不该被当成相对字号。
    expect(_styles(classes: const ['em10']), isNull);
  });
  test('两端对齐只作用于普通正文，显式对齐 class 优先', () {
    const justified = ReaderContentStyle(
      fontSize: 18,
      lineHeight: 1.6,
      color: Color(0xFF222222),
      firstLineIndent: true,
      justify: true,
    );
    expect(_styles(tag: 'p', style: justified), <String, String>{
      'margin': '0',
      'text-align': 'justify',
    });
    expect(
      _styles(tag: 'p', classes: const ['center'], style: justified),
      <String, String>{'margin': '0', 'text-align': 'center'},
    );
    expect(_styles(tag: 'div', style: justified), isNull);
  });

  test('h2 居中加粗且字号锁死', () {
    expect(_styles(tag: 'h2'), <String, String>{
      'font-size': '22.50px',
      'font-weight': 'bold',
      'text-align': 'center',
      'line-height': '1.2',
      'margin': '0.3em 0 0.5em',
    });
  });

  test('center class 与标签声明合并', () {
    expect(_styles(tag: 'p', classes: const ['center']), <String, String>{
      'margin': '0',
      'text-align': 'center',
    });
  });

  test('h4 与 pius/ph4 小标题居中且不使用左缩进', () {
    const expected = <String, String>{
      'font-size': '27.00px',
      'font-weight': 'bold',
      'text-align': 'center',
      'margin': '0.5em 0 1em',
    };
    expect(_styles(tag: 'h4'), expected);
    for (final className in const ['pius1', 'pius2', 'ph4']) {
      expect(_styles(classes: [className]), expected);
    }
  });

  test('font size 属性按历史倍率换算', () {
    expect(
      _styles(tag: 'font', attributes: const {'size': '6'})?['font-size'],
      '36.00px',
    );
    expect(_styles(tag: 'font', attributes: const {'size': '8'}), isNull);
    expect(_styles(tag: 'font'), isNull);
  });

  test('未命中任何规则返回 null', () {
    expect(_styles(tag: 'span', classes: const ['unknown-class']), isNull);
    expect(_styles(), isNull);
  });
}
