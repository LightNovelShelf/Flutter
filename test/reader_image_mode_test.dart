import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/reader/reader_footnotes.dart';
import 'package:lightnovel/features/reader/widgets/reader_footnote_sheet.dart';
import 'package:lightnovel/shared/widgets/blurhash_image.dart';
import 'package:lightnovel/shared/widgets/book_image.dart';
import 'package:lightnovel/shared/widgets/html/html_source.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_style.dart';
import 'package:lightnovel/shared/widgets/html_content.dart';
import 'package:lightnovel/shared/widgets/reader_html_block.dart';

const _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

ReaderContentStyle _style(ReaderImageMode mode) => ReaderContentStyle(
  fontSize: 16,
  lineHeight: 1.5,
  lineSpace: 8,
  firstLineIndent: false,
  justify: false,
  imageMode: mode,
);

String _image(String name, {String size = '300x400'}) =>
    '<img src="https://img.example/$name.webp?size=$size'
    '&amp;placeholder=$_hash">';

/// 走一遍正文分块，拿到阅读器真正交给渲染器的那份块 HTML。
String _block(String html) => parseRenderableHtmlBlocks(html).single.html;

const _subject = ValueKey<String>('subject');

Future<Size> _pump(
  WidgetTester tester,
  String markup,
  ReaderImageMode mode, {
  double bottomSpacing = 0,
  ReaderImageReveals? reveals,
  Key? blockKey,
}) async {
  debugBlurHashPixelDecoder = (_, {required width, required height}) =>
      Uint8List.fromList(List<int>.filled(width * height * 4, 255));
  addTearDown(() => debugBlurHashPixelDecoder = null);

  Widget block = SizedBox(
    key: _subject,
    width: 400,
    child: ReaderHtmlBlock(
      key: blockKey,
      markup: markup,
      style: _style(mode),
      bottomSpacing: bottomSpacing,
    ),
  );
  if (reveals != null) {
    block = ReaderImageRevealScope(reveals: reveals, child: block);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: block),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byKey(_subject));
}

Finder _paragraph(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
);

void main() {
  test('只有图片、没有文字的块才算纯图像块', () {
    expect(
      isReaderImageOnlyMarkup('<div class="illus"><img src="a"></div>'),
      isTrue,
    );
    expect(
      isReaderImageOnlyMarkup(
        '<p><reader-indent></reader-indent><img src="a"><br></p>',
      ),
      isTrue,
    );
    expect(isReaderImageOnlyMarkup('<p>&nbsp;<img src="a">　</p>'), isTrue);
    // 属性值里的 `>` 不转义，不能把它后面的半截当成正文。
    expect(isReaderImageOnlyMarkup('<p><img alt="甲 > 乙" src="a"></p>'), isTrue);
    // 零宽空格、零宽连接符、方向标记、软连字符看不见也不占地方，同样不算内容。
    for (final invisible in <int>[0x200B, 0x200D, 0x200E, 0x2060, 0xAD]) {
      expect(
        isReaderImageOnlyMarkup(
          '<p><img src="a">${String.fromCharCode(invisible)}</p>',
        ),
        isTrue,
        reason: 'U+${invisible.toRadixString(16).toUpperCase()}',
      );
    }

    expect(isReaderImageOnlyMarkup('<p>正文</p>'), isFalse);
    expect(isReaderImageOnlyMarkup('<p>前<img src="a">后</p>'), isFalse);
    expect(
      isReaderImageOnlyMarkup(
        '<p><img src="a"><a href="lnfootnote:1"><sup>[1]</sup></a></p>',
      ),
      isFalse,
    );
    expect(isReaderImageOnlyMarkup('<div><img src="a"><hr></div>'), isFalse);
  });

  test('不显示：脚注去掉图片，保留注文', () {
    expect(removeHtmlImages('<p>注<img src="a.png" alt="x">文</p>'), '<p>注文</p>');

    // 注文是从 DOM 序列化出来的，属性值里的 `>` 不转义：整个标签都要去掉，
    // 不能只删到第一个 `>`、把后半截留在注文里。
    final note = processNovelFootnotes(
      '<p>正文<a class="duokan-footnote" href="#n1">注</a></p>'
      '<ol><li id="n1">注<img alt="甲 &gt; 乙" src="a.png">文</li></ol>',
    ).notesById['n1']!;
    expect(note, contains('alt="甲 > 乙"'));
    expect(removeHtmlImages(note), '注文');
  });

  group('脚注弹层', () {
    Future<void> open(
      WidgetTester tester,
      String html,
      ReaderImageMode mode,
    ) async {
      debugBlurHashPixelDecoder = (_, {required width, required height}) =>
          Uint8List.fromList(List<int>.filled(width * height * 4, 255));
      addTearDown(() => debugBlurHashPixelDecoder = null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderFootnoteSheet(
                  context,
                  html: html,
                  imageMode: mode,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    final note = '<p>注文${_image('n', size: '40x60')}</p>';

    testWidgets('直接显示：注文里的图片照常显示', (tester) async {
      await open(tester, note, ReaderImageMode.show);
      expect(_paragraph('注文'), findsOneWidget);
      expect(find.byType(BookImage), findsOneWidget);
      expect(find.text('显示图像'), findsNothing);
    });

    testWidgets('不显示：略去图片，也不摆按钮', (tester) async {
      await open(tester, note, ReaderImageMode.hide);
      expect(_paragraph('注文'), findsOneWidget);
      expect(find.byType(BookImage), findsNothing);
      expect(find.text('显示图像'), findsNothing);
    });

    testWidgets('点击显示：先略去图片，点按钮后才显示', (tester) async {
      await open(tester, note, ReaderImageMode.tapToShow);
      expect(_paragraph('注文'), findsOneWidget);
      expect(find.byType(BookImage), findsNothing);

      await tester.tap(find.text('显示图像'));
      await tester.pump();
      expect(find.byType(BookImage), findsOneWidget);
      expect(find.text('显示图像'), findsNothing);
    });

    testWidgets('点击显示：注文里没有图片时不摆按钮', (tester) async {
      await open(tester, '<p>注文</p>', ReaderImageMode.tapToShow);
      expect(_paragraph('注文'), findsOneWidget);
      expect(find.text('显示图像'), findsNothing);
    });
  });

  testWidgets('不显示：纯图像块连同块底间距一起不占位，也不建图片组件', (tester) async {
    for (final html in <String>[
      '<div class="illus">${_image('a')}</div>',
      '<p class="illus">${_image('b')}</p>',
      '<center>${_image('c')}<br></center>',
    ]) {
      final markup = _block(html);
      final shown = await _pump(
        tester,
        markup,
        ReaderImageMode.show,
        bottomSpacing: 8,
      );
      expect(shown.height, greaterThan(100), reason: html);

      final hidden = await _pump(
        tester,
        markup,
        ReaderImageMode.hide,
        bottomSpacing: 8,
      );
      expect(hidden.height, 0, reason: html);
      expect(find.byType(BookImage), findsNothing, reason: html);
    }
  });

  testWidgets('不显示：段内图片只抽掉图片，前后文字接排在同一行', (tester) async {
    final markup = _block('<p>图片前文字${_image('d', size: '40x60')}图片后文字</p>');

    await _pump(tester, markup, ReaderImageMode.show);
    expect(
      tester.getSize(_paragraph('图片前文字')).height,
      greaterThanOrEqualTo(60),
    );

    await _pump(tester, markup, ReaderImageMode.hide);
    final paragraph = _paragraph('图片前文字');
    expect(paragraph, findsOneWidget);
    expect(
      tester.widget<RichText>(paragraph).text.toPlainText(),
      contains('图片后文字'),
    );
    // 一行字高 16 × 1.5，没有图片撑高。
    expect(tester.getSize(paragraph).height, lessThan(30));
    expect(find.byType(BookImage), findsNothing);
  });

  testWidgets('点击显示：遮罩与图像同尺寸，点开后原位换成图像', (tester) async {
    final markup = _block('<div class="illus">${_image('e')}</div>');
    final shown = await _pump(tester, markup, ReaderImageMode.show);
    final imageSize = tester.getSize(find.byType(BookImage));

    final masked = await _pump(tester, markup, ReaderImageMode.tapToShow);
    expect(masked, shown);
    expect(find.byType(BookImage), findsNothing);
    expect(find.text('显示图像'), findsOneWidget);

    // 胶囊按钮看得见的范围就是能点的范围：点在边上、不碰文字也能点开。
    final button = tester.getRect(find.bySubtype<OutlinedButton>());
    expect(button.width, greaterThanOrEqualTo(160));
    expect(button.height, greaterThanOrEqualTo(48));
    await tester.tapAt(button.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(find.text('显示图像'), findsNothing);
    expect(tester.getSize(find.byType(BookImage)), imageSize);
    expect(tester.getSize(find.byKey(_subject)), shown);
  });

  testWidgets('点击显示：点开的记在阅读器上，正文块重建后不必再点', (tester) async {
    final markup = _block('<div class="illus">${_image('f')}</div>');
    final reveals = ReaderImageReveals();
    addTearDown(reveals.dispose);

    await _pump(
      tester,
      markup,
      ReaderImageMode.tapToShow,
      reveals: reveals,
      blockKey: const ValueKey<int>(1),
    );
    await tester.tap(find.text('显示图像'));
    await tester.pump();
    expect(find.byType(BookImage), findsOneWidget);

    // 换 key 等于翻走再翻回来：块的 State 全新，点开与否只能从阅读器那份记录里读。
    await _pump(
      tester,
      markup,
      ReaderImageMode.tapToShow,
      reveals: reveals,
      blockKey: const ValueKey<int>(2),
    );
    expect(find.byType(BookImage), findsOneWidget);
    expect(find.text('显示图像'), findsNothing);

    // 没挂记录的地方，点开只在当前组件里有效。
    await _pump(
      tester,
      markup,
      ReaderImageMode.tapToShow,
      blockKey: const ValueKey<int>(3),
    );
    expect(find.byType(BookImage), findsNothing);
    expect(find.text('显示图像'), findsOneWidget);
  });

  testWidgets('点击显示：小图摆不下按钮，整块都可点', (tester) async {
    final markup = _block('<p>前文${_image('g', size: '40x60')}后文</p>');
    await _pump(tester, markup, ReaderImageMode.tapToShow);

    expect(find.text('显示图像'), findsNothing);
    final icon = find.byIcon(Icons.image_outlined);
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon).height, lessThanOrEqualTo(60));

    await tester.tap(icon);
    await tester.pump();
    expect(find.byType(BookImage), findsOneWidget);
    expect(tester.getSize(find.byType(BookImage)), const Size(40, 60));
  });
}
