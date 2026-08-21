import 'package:flutter/painting.dart';

/// 正文 class/标签的排版语义原本住在 `assets/css/novel_reader.css`，那份 CSS 随 WebView
/// 阅读器一并删除，此后只由本文件维护。

/// 正文样式来源。`stylesFor` 的返回值直接交给 HtmlWidget 的 `customStylesBuilder`，
/// 因此取值必须是它能解析的 CSS：`px`/`em`/`%` 长度、`bold`、`italic`、`center`、`#RRGGBB` 等。
class ReaderContentStyle {
  const ReaderContentStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.color,
    required this.firstLineIndent,
    required this.justify,
    this.paragraphSpacing = 0,
    this.fontFamily,
  });

  /// 正文基准字号（逻辑像素）。
  final double fontSize;

  /// 行高倍数。
  final double lineHeight;

  /// 正文色。
  final Color color;

  /// 普通正文段落之后的额外间距（逻辑像素）。
  final double paragraphSpacing;

  /// 段首缩进 2em。
  final bool firstLineIndent;

  /// 普通正文段落是否两端对齐。
  final bool justify;

  /// 章节混淆字体族名，null 用系统字体。
  final String? fontFamily;

  TextStyle get textStyle => TextStyle(
    fontSize: fontSize,
    height: lineHeight,
    color: color,
    fontFamily: fontFamily,
  );

  /// `<font size="1..7">` 的历史换算表，与简介渲染器共用一套倍率。
  static const List<double> _fontTagSizes = <double>[
    0.63,
    0.82,
    1,
    1.13,
    1.5,
    2,
    3,
  ];

  /// 这些 class 在原 CSS 里就带 `text-indent: 0`，段首不该再缩进。
  static const Set<String> _indentCancelling = <String>{
    'center',
    'left',
    'right',
    'zin',
    'message',
    'cut-line',
    'meg',
    'pius1',
    'pius2',
    'ph4',
  };

  /// HtmlWidget 不解析 `text-indent`，段首缩进只能由调用方往正文里插全角空格，
  /// 缩进与否的判定留在这里跟 CSS 语义放一起。
  bool indentsParagraph({
    required String? tag,
    required Iterable<String> classes,
  }) =>
      firstLineIndent && tag == 'p' && !classes.any(_indentCancelling.contains);

  Map<String, String>? stylesFor({
    required String? tag,
    required Iterable<String> classes,
    required Map<String, String> attributes,
  }) {
    final styles = <String, String>{};
    switch (tag) {
      case 'p':
        styles['margin'] = '0';
        if (justify) styles['text-align'] = 'justify';
      case 'h1':
        styles.addAll(_heading(1.65));
        styles['margin'] = '0.1em 0 0.4em';
      case 'h2':
        styles.addAll(_heading(1.25));
        styles['margin'] = '0.3em 0 0.5em';
      case 'h3':
        styles.addAll(_heading(0.95));
        styles['margin'] = '0.2em 0';
      case 'h4':
        styles.addAll(_subheading());
      case 'a':
        // 颜色留给继承：正文里的脚注/外链不该跳出正文色，只去掉下划线。
        styles['text-decoration'] = 'none';
      case 'img':
        styles['max-width'] = '100%';
      case 'table':
        styles['width'] = '100%';
        styles['margin'] = '0 0 0.8em';
      case 'th':
      case 'td':
        styles['padding'] = '0';
        styles['vertical-align'] = 'top';
      case 'rt':
        styles['font-size'] = '0.5em';
      case 'font':
        final size = int.tryParse(attributes['size'] ?? '');
        if (size != null && size >= 1 && size <= _fontTagSizes.length) {
          styles['font-size'] = _px(fontSize * _fontTagSizes[size - 1]);
        }
    }

    // class 后写，命中同一属性时覆盖标签默认值。
    for (final className in classes) {
      switch (className) {
        case 'right':
          styles['text-align'] = 'right';
        case 'left':
          styles['text-align'] = 'left';
        case 'center':
          styles['text-align'] = 'center';
        case 'bold':
          styles['font-weight'] = 'bold';
        case 'ita':
          styles['font-style'] = 'italic';
        case 'stress':
          styles['font-size'] = '1.1em';
          styles['font-weight'] = 'bold';
          styles['margin'] = '0.3em 0';
        case 'author':
          styles['font-size'] = '1.2em';
          styles['font-weight'] = 'bold';
          styles['font-style'] = 'italic';
          styles['text-align'] = 'right';
          styles['margin-right'] = '1em';
        case 'message':
        case 'cut-line':
          styles['line-height'] = '1.2em';
          styles['margin'] = '0.2em 0';
        case 'meg':
          styles['font-size'] = '1.3em';
          styles['line-height'] = '1.3em';
          styles['margin'] = '0.5em 0 0';
        case 'lh':
          styles['line-height'] = '1em';
        case 'm0':
          styles['margin'] = '0';
        case 'p0':
          styles['padding'] = '0';
        case 'no-d':
          styles['text-decoration'] = 'none';
        case 'red':
          styles['color'] = '#D32F2F';
        case 'green':
          styles['color'] = '#2E7D32';
        case 'blue':
          styles['color'] = '#1565C0';
        case 'black':
          styles['color'] = '#000000';
        case 'white':
          styles['color'] = '#FFFFFF';
        case 'dot':
        case 'em-dot':
          // 0.17.2 的解析器只认 text-emphasis / -color / -style，标记恒画在字上方，
          // 原 CSS 的 text-emphasis-position 没有对应实现，不吐。
          styles['text-emphasis'] = 'circle';
        case 'pius1':
        case 'pius2':
        case 'ph4':
          styles.addAll(_subheading());
        case 'illu':
        case 'illus':
        case 'duokan-image-single':
          styles['text-align'] = 'center';
        default:
          final scale = _emScale(className);
          if (scale != null) styles['font-size'] = _px(fontSize * scale);
      }
    }
    return styles.isEmpty ? null : styles;
  }

  /// 标题字号要跟 `line-height` 一起定死，用 em 会被外层相对字号二次放大。
  Map<String, String> _heading(double scale) => <String, String>{
    'font-size': _px(fontSize * scale),
    'font-weight': 'bold',
    'text-align': 'center',
    'line-height': '1.2',
  };

  Map<String, String> _subheading() => <String, String>{
    'font-size': _px(fontSize * 1.5),
    'font-weight': 'bold',
    'text-align': 'center',
    'margin': '0.5em 0 1em',
  };

  static String _px(double size) => '${size.toStringAsFixed(2)}px';

  /// 站内自造的 `em05`…`em30` 类名表示相对字号（跳过 em10）。
  static double? _emScale(String className) {
    if (className.length != 4 || !className.startsWith('em')) return null;
    final value = int.tryParse(className.substring(2));
    if (value == null || value < 5 || value > 30 || value == 10) return null;
    return value / 10;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderContentStyle &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.color == color &&
      other.firstLineIndent == firstLineIndent &&
      other.justify == justify &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    paragraphSpacing,
    color,
    firstLineIndent,
    justify,
    fontFamily,
  );
}
