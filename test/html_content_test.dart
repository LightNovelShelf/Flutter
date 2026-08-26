import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lightnovel/shared/widgets/html_content.dart';
import 'package:lightnovel/shared/widgets/html/html_source.dart';
import 'package:lightnovel/shared/widgets/blurhash_image.dart';
import 'package:lightnovel/shared/widgets/image_preview.dart';

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
    expect(widget.html, contains('<img src="https://example.com/a.png"'));
    expect(widget.html, contains(htmlImageBlockClass));
    expect(widget.textStyle?.fontFamily, 'NovelFont');
    expect(widget.onTapImage, isNotNull);
    expect(widget.textStyle?.height, 1.5);
  });

  testWidgets('官方图床图片按 URL 元数据预留尺寸并显示 BlurHash', (tester) async {
    const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    debugBlurHashPixelDecoder = (_, {required width, required height}) =>
        Uint8List.fromList(List<int>.filled(width * height * 4, 255));
    addTearDown(() => debugBlurHashPixelDecoder = null);
    ImageMetadata? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: HtmlContentTheme(
              data: HtmlContentThemeData(
                onTapImage: (metadata) => tapped = metadata,
              ),
              child: const HtmlContent(
                html:
                    '<img src="https://img.lightnovel.life/file/post.webp'
                    '?size=400x600&amp;placeholder=$hash" alt="插图">',
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<ContentImage>(find.byType(ContentImage));
    expect(image.url, contains('size=400x600&placeholder=$hash'));
    expect(image.blurHash, hash);
    expect(image.width, 200);
    expect(image.height, 300);
    expect(image.trigger, ImagePreviewTrigger.tap);
    expect(tester.getSize(find.byType(ContentImage)), const Size(200, 300));

    await tester.tap(find.byType(ContentImage));
    expect(tapped?.alt, '插图');
    expect(tapped?.sources.single.url, image.url);
  });

  testWidgets('没有图床元数据的图片继续交给 HTML 渲染器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HtmlContent(html: '<img src="https://example.com/post.webp">'),
      ),
    );

    expect(find.byType(ContentImage), findsNothing);
    expect(find.byType(HtmlWidget), findsOneWidget);
  });

  testWidgets('default renderer removes metadata and hidden nodes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HtmlContent(
          html:
              '<p>可见正文</p>'
              '<script>bad()</script>'
              '<style>.bad{}</style>'
              '<object>备用正文</object>'
              '<div hidden>hidden</div>'
              '<div aria-hidden="true">aria</div>'
              '<div style="display:none">display</div>'
              '<div style="visibility: hidden">visibility</div>',
        ),
      ),
    );

    final widget = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(widget.html, '<p>可见正文</p>');
  });

  test('common preprocessing assigns image block spacing once', () {
    const html =
        '<img src="bare.webp">'
        '<p><img src="paragraph.webp"></p>'
        '<div><img src="first.webp"><img src="second.webp"></div>'
        '<p>正文</p>';
    final blocks = parseRenderableHtmlBlocks(html);

    expect(blocks, hasLength(5));
    expect(blocks[0], isA<ReaderImageBlock>());
    expect(blocks[1], isA<ReaderMarkupBlock>());
    expect(blocks[2], isA<ReaderImageBlock>());
    expect(blocks[3], isA<ReaderImageBlock>());
    expect(blocks[4], isA<ReaderMarkupBlock>());
    expect(blocks[0].html, isNot(contains(htmlImageSpacingClass)));
    expect(blocks[1].html, isNot(contains(htmlImageBlockClass)));
    expect(blocks[2].html, contains(htmlImageSpacingClass));
    expect(blocks[3].html, isNot(contains(htmlImageSpacingClass)));
    expect(
      prepareRenderableHtml(html),
      blocks.map((block) => block.html).join(),
    );
  });

  testWidgets('default renderer applies the common image block spacing style', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HtmlContent(
          html: '<div><img src="first.webp"><img src="second.webp"></div>',
        ),
      ),
    );

    final widget = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    final image = dom.Element.tag('img')
      ..classes.addAll(<String>[htmlImageBlockClass, htmlImageSpacingClass]);
    final styles = widget.customStylesBuilder?.call(image);
    expect(styles?['display'], 'block');
    expect(styles?['margin-bottom'], '8.00px');
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
