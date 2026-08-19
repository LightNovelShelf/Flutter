import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_content_css.dart';
import 'package:lightnovel/features/reader/reader_engine.dart';
import 'package:lightnovel/features/reader/reader_html_builder.dart';

const ReaderTypography _typography = ReaderTypography(
  backgroundColor: '#ffffff',
  textColor: '#111111',
  fontSize: 18,
  lineHeight: 1.8,
  sidePadding: 20,
  topPadding: 24,
  bottomPadding: 24,
  firstLineIndent: true,
);

String _document({bool paged = false}) => buildReaderChapterDocument(
  blocks: const <NovelReaderBlock>[
    NovelReaderBlock(
      id: 'b0',
      locator: 'body/p[1]',
      html: '<p class="center">正文</p>',
      textLength: 2,
      imageCount: 0,
    ),
  ],
  fallbackHtml: '',
  imageBaseUrl: 'https://api.example',
  typography: _typography,
  paged: paged,
  readerScriptSource: '',
);

void main() {
  test('字号类按 .emNN 的十分之一倍生成', () {
    expect(readerContentCss.contains('.em05{font-size:0.5em}'), isTrue);
    expect(readerContentCss.contains('.em12{font-size:1.2em}'), isTrue);
    expect(readerContentCss.contains('.em30{font-size:3.0em}'), isTrue);
  });

  test('书源类名样式排在基础排版之后、多列布局之前', () {
    final html = _document(paged: true);
    final base = html.indexOf('text-indent:var(--nv-indent)');
    final preset = html.indexOf('.center{text-indent:0;text-align:center}');
    final layout = html.indexOf('column-width:100vw');
    expect(base, greaterThan(-1));
    expect(preset, greaterThan(base));
    expect(layout, greaterThan(preset));
  });
}
