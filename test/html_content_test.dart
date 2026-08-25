import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lightnovel/shared/widgets/html_content.dart';

void main() {
  test('compact source removes scripts and images but preserves blocks', () {
    final source = createCompactHtmlSource(
      '<script>bad()</script><h2>标题</h2><p>正文</p><img src="x">',
    );

    expect(source, isNot(contains('script')));
    expect(source, isNot(contains('<img')));
    expect(source, contains('<h2>标题</h2>'));
    expect(source, contains('<p>正文</p>'));
  });

  testWidgets('full HTML uses common image interaction and custom font', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HtmlContentTheme(
          data: HtmlContentThemeData(
            textStyle: TextStyle(fontFamily: 'NovelFont'),
          ),
          child: HtmlContent(
            html: '<a href="https://example.com"><img src="https://example.com/a.png"></a>',
          ),
        ),
      ),
    );

    final widget = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(widget.html, '<img src="https://example.com/a.png">');
    expect(widget.textStyle?.fontFamily, 'NovelFont');
    expect(widget.onTapImage, isNotNull);
    expect(widget.textStyle?.height, 1.5);
  });

  testWidgets('compact mode disables image interaction', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HtmlContent.compact(html: '<p>正文</p><img src="x">'),
      ),
    );

    final widget = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(widget.html, isNot(contains('<img')));
    expect(widget.onTapImage, isNull);
    expect(widget.textStyle?.height, 1.3);
  });

  testWidgets('compact paragraphs have no bottom spacing', (tester) async {
    Future<double> height(String html) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: HtmlContent.compact(key: ValueKey(html), html: html),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(HtmlWidget)).height;
    }

    final singleHeight = await height('<p>第一段</p>');
    final doubleHeight = await height('<p>第一段</p><p>第二段</p>');
    expect(doubleHeight - singleHeight, closeTo(18.2, 0.3));
  });

  testWidgets('compact content can be clipped without flex overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: ClipRect(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: HtmlContent.compactLineExtentOf(context) * 5,
                  ),
                  child: const OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    fit: OverflowBoxFit.deferToChild,
                    child: SizedBox(
                      width: 371.4,
                      child: HtmlContent.compact(
                        html: '<p>第一行<br>第二行<br>第三行<br>第四行<br>第五行<br>第六行</p>',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final viewport = find.byType(OverflowBox);
    expect(tester.getSize(viewport).height, closeTo(113.75, 0.1));
    final paragraphFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('第五行'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(paragraphFinder);
    final plainText = tester
        .widget<RichText>(paragraphFinder)
        .text
        .toPlainText();
    TextBox boxFor(String line) {
      final start = plainText.indexOf(line);
      return paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 3),
          )
          .single;
    }

    final paragraphTop = tester.getTopLeft(paragraphFinder).dy;
    final viewportBottom = tester.getBottomLeft(viewport).dy;
    expect(paragraphTop + boxFor('第五行').bottom, lessThan(viewportBottom));
    expect(paragraphTop + boxFor('第六行').top, greaterThan(viewportBottom));
  });

  testWidgets('theme can replace source and disable every default hook', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HtmlContentTheme(
          data: HtmlContentThemeData(
            sourceTransformer: (_) => '<p>替换正文</p>',
            enableDefaultTextStyle: false,
            enableDefaultStyles: false,
            enableDefaultImagePreview: false,
            enableDefaultUrlLauncher: false,
            enableDefaultErrorBuilder: false,
            enableDefaultLoadingBuilder: false,
            onTapUrl: (_) {
              opened = true;
              return true;
            },
          ),
          child: const HtmlContent(html: '<p>原正文</p>'),
        ),
      ),
    );

    final widget = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(widget.html, '<p>替换正文</p>');
    expect(widget.textStyle, isNull);
    expect(widget.onTapImage, isNull);
    expect(widget.onErrorBuilder, isNull);
    expect(widget.onLoadingBuilder, isNull);
    expect(await widget.onTapUrl?.call('custom'), isTrue);
    expect(opened, isTrue);
  });

  testWidgets('default paragraphs apply line height and bottom spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          child: HtmlContent(html: '<p>第一段</p><p>第二段</p>'),
        ),
      ),
    );

    Finder paragraph(String text) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    );
    final first = paragraph('第一段');
    final second = paragraph('第二段');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(
      tester.getTopLeft(second).dy - tester.getTopLeft(first).dy,
      closeTo(32, 0.3),
    );
  });
}
