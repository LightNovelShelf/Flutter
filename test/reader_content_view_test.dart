import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_html_blocks.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_style.dart';
import 'package:lightnovel/shared/widgets/blurhash_image.dart';
import 'package:lightnovel/shared/widgets/book_image.dart';
import 'package:lightnovel/shared/widgets/image_preview.dart';
import 'package:lightnovel/features/reader/widgets/reader_content_view.dart';

const ReaderContentStyle _style = ReaderContentStyle(
  fontSize: 18,
  lineHeight: 1.6,
  color: Color(0xFF000000),
  firstLineIndent: false,
  justify: false,
);

/// 每段都够长，确保一屏装不下、必须分成多页。
List<NovelReaderBlock> _blocks([int count = 40, String label = '第']) =>
    normalizeNovelBlocks(
      List<String>.generate(
        count,
        (index) =>
            '<p>$label$index段 这是一段用来测试原生分页与定位的正文，'
            '长度足够触发换行，好让每一页里都落进若干行。</p>',
      ).join(),
    );

ReaderChapterContent _chapter(int sortNum, {int count = 12}) =>
    ReaderChapterContent(
      sortNum: sortNum,
      blocks: _blocks(count, '第$sortNum章第'),
      style: _style,
    );

class _Harness {
  _Harness({
    required List<NovelReaderBlock> blocks,
    required this.paged,
    this.previous,
    this.next,
    this.restoreLocator,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 24),
    ReaderContentStyle style = _style,
    int sortNum = 2,
  }) : chapter = ReaderChapterContent(
         sortNum: sortNum,
         blocks: blocks,
         style: style,
       );

  ReaderChapterContent chapter;
  ReaderChapterContent? previous;
  ReaderChapterContent? next;

  final bool paged;
  String? restoreLocator;
  final EdgeInsets padding;
  int restoreToken = 0;

  final List<ReaderContentPosition> positions = <ReaderContentPosition>[];
  final List<bool> boundaries = <bool>[];
  final List<int> chapters = <int>[];
  int centerTaps = 0;
  int ready = 0;

  List<NovelReaderBlock> get blocks => chapter.blocks;
  ReaderContentPosition get last => positions.last;

  /// 上层收到 [ReaderContentView.onChapterChanged] 后该做的事：窗口整体挪一格。
  void shiftTo(int sortNum) {
    final target = sortNum == next?.sortNum ? next! : previous!;
    final forward = sortNum > chapter.sortNum;
    final leaving = chapter;
    chapter = target;
    previous = forward ? leaving : null;
    next = forward ? null : leaving;
  }

  Widget build() => MaterialApp(
    home: Scaffold(
      body: ReaderContentView(
        chapter: chapter,
        previous: previous,
        next: next,
        paged: paged,
        padding: padding,
        restoreLocator: restoreLocator,
        restoreProgression: 0,
        restoreToken: restoreToken,
        onPosition: positions.add,
        onTapCenter: () => centerTaps++,
        onChapterChanged: chapters.add,
        onBoundary: boundaries.add,
        onFootnote: (_, _) {},
        onReady: () => ready++,
      ),
    ),
  );
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool paged = true,
  String? restoreLocator,
  int count = 40,
  ReaderChapterContent? previous,
  ReaderChapterContent? next,
}) async {
  final harness = _Harness(
    blocks: _blocks(count),
    paged: paged,
    previous: previous,
    next: next,
    restoreLocator: restoreLocator,
  );
  await tester.pumpWidget(harness.build());
  await tester.pumpAndSettle();
  return harness;
}

const ReaderContentStyle _justifiedIndentedStyle = ReaderContentStyle(
  fontSize: 18,
  lineHeight: 1.6,
  color: Color(0xFF000000),
  firstLineIndent: true,
  justify: true,
);

/// 翻页条上真正画出来的正文；测量层的同名文本不算。
Finder _pageText(String text) => find.descendant(
  of: find.byType(PageView),
  matching: find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  ),
);

void main() {
  testWidgets('段间距动态更新后实际增加相邻段落距离', (tester) async {
    final blocks = normalizeNovelBlocks('<p>甲</p><p>乙</p>');
    Future<double> paragraphAdvance(double paragraphSpacing) async {
      final style = ReaderContentStyle(
        fontSize: 20,
        lineHeight: 1.5,
        paragraphSpacing: paragraphSpacing,
        color: Colors.black,
        firstLineIndent: false,
        justify: false,
      );
      final harness = _Harness(
        blocks: blocks,
        paged: false,
        padding: EdgeInsets.zero,
        style: style,
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      Finder paragraph(String text) => find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains(text),
        ),
      );
      return tester.getTopLeft(paragraph('乙').first).dy -
          tester.getTopLeft(paragraph('甲').first).dy;
    }

    final withoutSpacing = await paragraphAdvance(0);
    final withSpacing = await paragraphAdvance(4);

    expect(withSpacing - withoutSpacing, closeTo(4, 0.5));
  });

  testWidgets('两端对齐时首行缩进保持固定 2em', (tester) async {
    final harness = _Harness(
      blocks: normalizeNovelBlocks('<p>${'正文内容' * 40}</p>'),
      paged: false,
      padding: EdgeInsets.zero,
      style: _justifiedIndentedStyle,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    final paragraph = find
        .descendant(
          of: find.byType(ReaderContentView),
          matching: find.byType(RichText),
        )
        .first;
    final renderParagraph = tester.renderObject<RenderParagraph>(paragraph);
    final indentBox = renderParagraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    final firstGlyph = renderParagraph.getBoxesForSelection(
      const TextSelection(baseOffset: 1, extentOffset: 2),
    );

    expect(renderParagraph.text.toPlainText(), startsWith('\uFFFC正文'));
    expect(indentBox, hasLength(1));
    expect(indentBox.single.right - indentBox.single.left, closeTo(36, 0.01));
    expect(firstGlyph, hasLength(1));
    expect(firstGlyph.single.left, closeTo(36, 0.5));
  });

  testWidgets('翻页模式测量出多页，点击右侧热区往后翻', (tester) async {
    final harness = await _pump(tester);

    expect(harness.ready, 1);
    expect(harness.last.pages, greaterThan(1));
    expect(harness.last.page, 1);
    expect(harness.last.locator, harness.blocks.first.locator);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(harness.last.page, 2);
    expect(harness.last.locator, isNot(harness.blocks.first.locator));
    expect(harness.last.progression, greaterThan(0));
  });

  testWidgets('翻页只在行距处下刀：跨页的长段落在下一页从整行开始', (tester) async {
    final harness = _Harness(
      blocks: normalizeNovelBlocks('<p>${'字' * 2000}</p>'),
      paged: true,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(harness.blocks, hasLength(1));
    expect(harness.last.pages, greaterThan(2));

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    // 第二页里那个段落被整体上移了「页顶偏移」这么多，段顶在屏幕上就是 12 - 偏移。
    final paragraph = find
        .descendant(of: find.byType(PageView), matching: find.byType(RichText))
        .first;
    final pageTop = 12 - tester.getTopLeft(paragraph).dy;
    // 行距由测试字体的实际度量决定，只能反推：段高 / 行数。
    final height = tester.getSize(paragraph).height;
    final advance = height / (height / (18 * 1.6)).round();
    final residue = pageTop % advance;
    expect(pageTop, greaterThan(0));
    expect(math.min(residue, advance - residue), lessThan(0.5));
  });

  testWidgets('页底不留下一页的首行：可见高度恰好裁到下一页页顶', (tester) async {
    final harness = _Harness(
      blocks: normalizeNovelBlocks('<p>${'字' * 2000}</p>'),
      paged: true,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    final visible = tester.getSize(find.byKey(readerPageBodyKey(2, 0))).height;

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    final paragraph = find
        .descendant(of: find.byType(PageView), matching: find.byType(RichText))
        .first;
    // 下一页把段落整体上移了 pageTop；本页可见高度必须等于它，多一点就会重画那一行。
    final pageTop = 12 - tester.getTopLeft(paragraph).dy;

    expect(visible, closeTo(pageTop, 0.5));
  });

  testWidgets('重排后控制器还没挂上就点热区：照常翻页，不撞 assert', (tester) async {
    final harness = await _pump(tester);

    // 改留白会重新测量并换掉 PageController；这一帧末尾只把状态标脏，
    // PageView 要到下一帧才认领新控制器，此时点热区就会撞上未挂载的控制器。
    final resized = _Harness(
      blocks: harness.blocks,
      paged: true,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
    )..positions.addAll(harness.positions);
    await tester.pumpWidget(resized.build());
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(resized.last.page, 2);
  });

  testWidgets('首页再往前翻交给上层翻章，中间点击只切工具栏', (tester) async {
    final harness = await _pump(tester);

    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();
    expect(harness.boundaries, <bool>[false]);
    expect(harness.last.page, 1);

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(harness.centerTaps, 1);
  });

  testWidgets('末页再往后翻同样交给上层翻章', (tester) async {
    final harness = await _pump(tester, count: 12);

    expect(harness.last.pages, greaterThan(1));
    while (harness.last.page < harness.last.pages) {
      final page = harness.last.page;
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
      expect(harness.last.page, page + 1);
    }
    expect(harness.last.progression, 1);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    expect(harness.boundaries, <bool>[true]);
  });

  testWidgets('按页顶 locator 恢复：回到同一页同一位置', (tester) async {
    final first = await _pump(tester);
    await tester.tapAt(const Offset(700, 300));
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    final page = first.last.page;
    final locator = first.last.locator;
    expect(page, 3);

    final restored = await _pump(tester, restoreLocator: locator);

    expect(restored.last.page, page);
    expect(restored.last.locator, locator);
  });

  testWidgets('滚动模式：滑动后进度与 locator 同步前进', (tester) async {
    final harness = await _pump(tester, paged: false);

    expect(harness.ready, 1);
    expect(harness.last.pages, 0);
    expect(harness.last.progression, 0);
    final first = harness.last.locator;

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    // 上报有 250ms 节流，滑动停下后还要让尾巴上那次补报跑掉。
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.last.progression, greaterThan(0));
    expect(harness.last.locator, isNot(first));
  });

  testWidgets('切换分页方式后仍钉在原来的 locator 上', (tester) async {
    final harness = await _pump(tester);
    await tester.tapAt(const Offset(700, 300));
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    final locator = harness.last.locator;

    final scrolling = _Harness(blocks: harness.blocks, paged: false)
      ..positions.addAll(harness.positions);
    await tester.pumpWidget(scrolling.build());
    await tester.pumpAndSettle();

    expect(scrolling.last.pages, 0);
    expect(scrolling.last.locator, locator);
  });
  testWidgets('站内正文图使用 URL 元数据，并统一保留 6px 下边距', (tester) async {
    const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    debugBlurHashPixelDecoder = (_, {required width, required height}) =>
        Uint8List.fromList(List<int>.filled(width * height * 4, 255));
    addTearDown(() => debugBlurHashPixelDecoder = null);

    String image(String name) =>
        '<div class="illus duokan-image-single"><img '
        'src="https://img.example/$name.webp?size=40x60'
        '&amp;placeholder=$hash"/></div>';
    final harness = _Harness(
      blocks: normalizeNovelBlocks(
        '${image('first')}${image('second')}<p>图片后的正文</p>',
      ),
      paged: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pump();

    Finder imagesNamed(String name) => find.byWidgetPredicate(
      (widget) => widget is BookImage && widget.url.contains('/$name.webp?'),
    );
    final firstImages = imagesNamed('first');
    final secondImages = imagesNamed('second');
    expect(firstImages, findsWidgets);
    expect(secondImages, findsWidgets);
    for (final bookImage in tester.widgetList<BookImage>(
      find.byType(BookImage),
    )) {
      expect(bookImage.blurHash, hash);
      expect(bookImage.aspectRatio, 1.5);
    }
    expect(tester.getSize(firstImages.first).height, 60);

    final previewImage = firstImages.hitTestable().first;
    await tester.tap(previewImage);
    await tester.pump();
    expect(find.byKey(imagePreviewTransformKey), findsNothing);

    await tester.longPress(previewImage);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(imagePreviewTransformKey), findsOneWidget);
    Navigator.of(tester.element(find.byKey(imagePreviewTransformKey))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final borderedImage = find.ancestor(
      of: firstImages.first,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
      ),
    );
    expect(tester.getSize(borderedImage.first), const Size(40, 60));

    Iterable<Padding> marginsOf(Finder images) => tester.widgetList<Padding>(
      find.ancestor(of: images, matching: find.byType(Padding)),
    );
    bool hasEdge(Iterable<Padding> margins, {double? top, double? bottom}) =>
        margins.any((padding) {
          final edge = padding.padding.resolve(TextDirection.ltr);
          return (top == null || edge.top == top) &&
              (bottom == null || edge.bottom == bottom);
        });

    expect(hasEdge(marginsOf(firstImages), top: 6), isFalse);
    expect(hasEdge(marginsOf(secondImages), top: 6), isFalse);
    expect(hasEdge(marginsOf(firstImages), bottom: 6), isTrue);
    expect(hasEdge(marginsOf(secondImages), bottom: 6), isTrue);
  });

  testWidgets('末页再往后翻直接进下一章：不走加载，窗口挪过来也不重排', (tester) async {
    final harness = await _pump(tester, count: 12, next: _chapter(3));
    final pages = harness.last.pages;
    expect(pages, greaterThan(1));
    expect(harness.last.sortNum, 2);

    for (var page = 1; page < pages; page++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
    }
    expect(harness.last.page, pages);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(harness.boundaries, isEmpty);
    expect(harness.chapters, <int>[3]);
    expect(harness.last.sortNum, 3);
    expect(harness.last.page, 1);
    expect(_pageText('第3章第0段'), findsWidgets);

    // 上层挪窗口：测量结果与正文块照旧留用，既不重新就绪也不退回旧章。
    harness.shiftTo(3);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(harness.ready, 1);
    expect(harness.last.sortNum, 3);
    expect(harness.last.page, 1);
    expect(_pageText('第3章第0段'), findsWidgets);
  });

  testWidgets('滑动跨章：一次拖拽直接翻进下一章', (tester) async {
    final harness = await _pump(tester, count: 12, next: _chapter(3));
    for (var page = 1; page < harness.last.pages; page++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
    }

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(harness.boundaries, isEmpty);
    expect(harness.chapters, <int>[3]);
    expect(harness.last.sortNum, 3);
    expect(harness.last.page, 1);
  });

  testWidgets('首页再往前翻进上一章：落在上一章末页', (tester) async {
    final harness = await _pump(tester, count: 12, previous: _chapter(1));
    expect(harness.last.page, 1);

    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();

    expect(harness.boundaries, isEmpty);
    expect(harness.chapters, <int>[1]);
    expect(harness.last.sortNum, 1);
    expect(harness.last.page, harness.last.pages);
    expect(harness.last.progression, 1);
  });

  testWidgets('上一章半路接进翻页条：当前页不动，往前翻不再交给上层', (tester) async {
    final harness = await _pump(tester, count: 12);
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    final page = harness.last.page;
    final locator = harness.last.locator;
    expect(page, 2);

    harness.previous = _chapter(1);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(harness.last.sortNum, 2);
    expect(harness.last.page, page);
    expect(harness.last.locator, locator);
    // 画出来的必须还是本章那一页：换控制器时页序整体后移过，别悄悄错位。
    expect(find.byKey(readerPageBodyKey(2, 1)), findsOneWidget);

    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();

    expect(harness.boundaries, isEmpty);
    expect(harness.chapters, <int>[1]);
    expect(harness.last.sortNum, 1);
  });

  testWidgets('目录跳进已备好的相邻章：钉在章首，不重新测量', (tester) async {
    final previous = _chapter(1);
    final harness = await _pump(tester, count: 12, previous: previous);

    harness.shiftTo(1);
    harness.restoreLocator = previous.blocks.first.locator;
    harness.restoreToken++;
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(harness.ready, 1);
    expect(harness.last.sortNum, 1);
    expect(harness.last.page, 1);
    expect(harness.last.locator, previous.blocks.first.locator);
    expect(find.byKey(readerPageBodyKey(1, 0)), findsOneWidget);
  });
}
