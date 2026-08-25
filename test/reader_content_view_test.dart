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
import 'package:lightnovel/features/reader/widgets/reader_measure_box.dart';
import 'package:lightnovel/features/reader/widgets/reader_page_body.dart';

const ReaderContentStyle _style = ReaderContentStyle(
  fontSize: 18,
  lineHeight: 1.6,
  firstLineIndent: false,
  justify: false,
);

/// 生成足够长的段落，使内容一屏放不下而分成多页。
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
    this.dualPage = false,
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
  final bool dualPage;
  String? restoreLocator;
  final EdgeInsets padding;
  int restoreToken = 0;
  Color textColor = const Color(0xFF2A2318);
  final ReaderContentController controller = ReaderContentController();

  final List<ReaderContentPosition> positions = <ReaderContentPosition>[];
  final List<bool> boundaries = <bool>[];
  final List<int> chapters = <int>[];
  int centerTaps = 0;
  int ready = 0;

  List<NovelReaderBlock> get blocks => chapter.blocks;
  ReaderContentPosition get last => positions.last;

  /// 模拟上层在 [ReaderContentView.onChapterChanged] 之后把章节窗口平移一格。
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
      body: DefaultTextStyle.merge(
        style: TextStyle(color: textColor),
        child: ReaderContentView(
          chapter: chapter,
          previous: previous,
          next: next,
          paged: paged,
          dualPage: dualPage,
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
          controller: controller,
        ),
      ),
    ),
  );
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool paged = true,
  bool dualPage = false,
  String? restoreLocator,
  int count = 40,
  ReaderChapterContent? previous,
  ReaderChapterContent? next,
}) async {
  final harness = _Harness(
    blocks: _blocks(count),
    paged: paged,
    dualPage: dualPage,
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
  firstLineIndent: true,
  justify: true,
);

/// 翻页条内渲染的正文，排除测量层中的同名文本。
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
        of: find.byType(ListView),
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

  /// 正文里第一处显式颜色，取自 span 树。
  Color? pageTextColor(WidgetTester tester, String text) {
    Color? found;
    void walk(InlineSpan span) {
      found ??= span.style?.color;
      if (found != null) return;
      span.visitChildren((child) {
        walk(child);
        return found == null;
      });
    }

    walk(tester.widgetList<RichText>(_pageText(text)).first.text);
    return found;
  }

  testWidgets('换正文色只重画文字，不重建正文块也不重新分页', (tester) async {
    final harness = await _pump(tester);
    final pages = harness.last.pages;
    final reports = harness.positions.length;
    expect(pageTextColor(tester, '第0段'), const Color(0xFF2A2318));

    harness.textColor = const Color(0xFFE2E5E6);
    await tester.pumpWidget(harness.build());
    await tester.pump();

    // 一帧就换色：颜色不进 ReaderContentStyle，不触发整章重建与逐片重测。
    expect(pageTextColor(tester, '第0段'), const Color(0xFFE2E5E6));
    expect(harness.ready, 1);
    expect(harness.last.pages, pages);
    expect(harness.positions.length, reports);
  });

  testWidgets('外部控制器可触发前后翻页', (tester) async {
    final harness = await _pump(tester);

    harness.controller.nextPage();
    await tester.pumpAndSettle();
    expect(harness.last.page, 2);

    harness.controller.previousPage();
    await tester.pumpAndSettle();
    expect(harness.last.page, 1);
  });

  // 一步 95% 视口再退到最近的行距处，落点在 (step - 一行, step] 内。
  void expectAlignedStep(ScrollPosition position, double step) {
    expect(position.pixels, lessThanOrEqualTo(step + 0.5));
    expect(position.pixels, greaterThan(step - _style.fontSize * 2));
  }

  testWidgets('滚动模式下外部控制器按 95% 视口翻屏并对齐行距', (tester) async {
    final harness = await _pump(tester, paged: false);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    final step = position.viewportDimension * 0.95;

    expect(position.pixels, 0);
    harness.controller.nextPage();
    await tester.pump(const Duration(milliseconds: 300));

    expectAlignedStep(position, step);
    expect(harness.last.progression, greaterThan(0));

    harness.controller.previousPage();
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.pixels, closeTo(0, 0.5));
  });

  testWidgets('滚动模式热区上下翻屏、中间切工具栏', (tester) async {
    final harness = await _pump(tester, paged: false);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    final view = tester.getRect(find.byType(ReaderContentView));
    final step = position.viewportDimension * 0.95;

    await tester.tapAt(Offset(view.center.dx, view.bottom - view.height * 0.1));
    await tester.pump(const Duration(milliseconds: 300));
    expectAlignedStep(position, step);
    expect(harness.centerTaps, 0);

    await tester.tapAt(Offset(view.center.dx, view.top + view.height * 0.1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.pixels, closeTo(0, 0.5));

    await tester.tapAt(view.center);
    await tester.pump();
    expect(harness.centerTaps, 1);
    expect(position.pixels, closeTo(0, 0.5));
  });

  testWidgets('滚动模式到底再往下翻交给上层翻章', (tester) async {
    final harness = await _pump(tester, paged: false, count: 6);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;

    while (position.pixels < position.maxScrollExtent) {
      harness.controller.nextPage();
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(harness.boundaries, isEmpty);

    harness.controller.nextPage();
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.boundaries, <bool>[true]);
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

    // 第二页的段落整体上移了页顶偏移，段顶的屏幕坐标为 12 减去该偏移。
    final paragraph = find
        .descendant(of: find.byType(PageView), matching: find.byType(RichText))
        .first;
    final pageTop = 12 - tester.getTopLeft(paragraph).dy;
    // 行距由测试字体的实际度量决定，只能用段高除以行数反推。
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
    // 下一页把段落上移 pageTop，本页可见高度须与之相等，否则会重复渲染该行。
    final pageTop = 12 - tester.getTopLeft(paragraph).dy;

    expect(visible, closeTo(pageTop, 0.5));
  });

  testWidgets('重排后控制器还没挂上就点热区：照常翻页，不撞 assert', (tester) async {
    final harness = await _pump(tester);

    // 改留白会重新测量并替换 PageController，本帧末尾只标脏，PageView 下一帧
    // 才接管新控制器。这期间点热区会用到尚未挂载的控制器。
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

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    // 上报有 250ms 节流，滑动停止后还需等待最后一次补报。
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

  testWidgets('换排版后重测期间：正文照旧显示，块与几何不脱节', (tester) async {
    final harness = await _pump(tester, paged: false, count: 30);
    expect(find.byType(ListView), findsOneWidget);

    // 正文块整批重建、几何要按分片重测，这期间渲染层必须仍有一批对得上的块可摆。
    harness.chapter = ReaderChapterContent(
      sortNum: harness.chapter.sortNum,
      blocks: harness.blocks,
      style: const ReaderContentStyle(
        fontSize: 26,
        lineHeight: 1.6,
        firstLineIndent: false,
        justify: false,
      ),
    );
    await tester.pumpWidget(harness.build());
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
    }

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
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

  testWidgets('测量层不建图片组件，分页几何照常按图片尺寸算', (tester) async {
    const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    debugBlurHashPixelDecoder = (_, {required width, required height}) =>
        Uint8List.fromList(List<int>.filled(width * height * 4, 255));
    addTearDown(() => debugBlurHashPixelDecoder = null);

    final harness = _Harness(
      blocks: normalizeNovelBlocks(
        '<div class="illus duokan-image-single"><img '
        'src="https://img.example/only.webp?size=40x60&amp;placeholder=$hash"/>'
        '</div><p>图片后的正文</p>',
      ),
      paged: false,
    );
    await tester.pumpWidget(harness.build());

    // 测量层只在测量期间挂着，逐帧看：这一层里一个图片组件都不许有。
    final measureLayer = find.byKey(const ValueKey<String>('reader-measure'));
    var measured = false;
    for (var frame = 0; frame < 6; frame++) {
      if (measureLayer.evaluate().isNotEmpty) {
        measured = true;
        expect(
          find.descendant(of: measureLayer, matching: find.byType(BookImage)),
          findsNothing,
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(measured, isTrue);

    await tester.pumpAndSettle();
    expect(find.byType(BookImage), findsOneWidget);

    // 图片块的高度仍是「按 URL 元数据算出的 60 + 6px 下边距」，几何没变。
    expect(tester.getSize(find.byType(ReaderBlockBox).first).height, 66);
  });

  testWidgets('尺寸未知的图不挡正文：先按 2:3 占位出画面，不等图片下载', (tester) async {
    final harness = _Harness(
      blocks: normalizeNovelBlocks(
        '<div class="illus duokan-image-single">'
        '<img src="https://img.example/unknown.webp"/></div><p>图片后的正文</p>',
      ),
      paged: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 图片一张都没加载成功（测试环境的请求一律 400），正文照样已经摆出来了。
    expect(harness.ready, 1);
    expect(find.byType(ListView), findsOneWidget);
    expect(harness.positions, isNotEmpty);

    // 几何按占位尺寸算：正文宽 800-24-24，占位比例 2:3，外加 6px 图片下边距。
    const width = 800 - 48.0;
    expect(
      tester.getSize(find.byType(ReaderBlockBox).first).height,
      width * 3 / 2 + 6,
    );
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

    // 上层平移窗口后复用测量结果与正文块，不重新就绪也不退回旧章。
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
    // 换控制器时页序整体后移，渲染的仍须是本章同一页。
    expect(find.byKey(readerPageBodyKey(2, 1)), findsOneWidget);

    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();

    expect(harness.boundaries, isEmpty);
    expect(harness.chapters, <int>[1]);
    expect(harness.last.sortNum, 1);
  });

  testWidgets('双页模式：两栏并排半屏，一屏摆连续的两栏', (tester) async {
    // 单栏跑一遍同样宽度的正文，拿到栏数，双页的屏数应当是它的一半（向上取整）。
    final narrow = _Harness(
      blocks: _blocks(40),
      paged: true,
      padding: const EdgeInsets.fromLTRB(220, 12, 220, 24),
    );
    await tester.pumpWidget(narrow.build());
    await tester.pumpAndSettle();
    final columns = narrow.last.pages;
    expect(columns, greaterThan(2));

    final harness = await _pump(tester, count: 40, dualPage: true);

    expect(harness.last.pages, (columns + 1) ~/ 2);
    expect(harness.last.page, 1);

    // 左右两栏各占半屏：外侧照旧留白，内侧各让出一半栏间距。
    final left = tester.getRect(find.byKey(readerPageBodyKey(2, 0)));
    final right = tester.getRect(find.byKey(readerPageBodyKey(2, 1)));
    expect(left.left, closeTo(24, 0.01));
    expect(left.width, closeTo(360, 0.01));
    expect(right.left, closeTo(416, 0.01));
    expect(right.width, closeTo(360, 0.01));
    expect(find.byKey(readerPageBodyKey(2, 2)), findsNothing);

    // 翻一屏走两栏。
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(harness.last.page, 2);
    expect(
      tester.getRect(find.byKey(readerPageBodyKey(2, 2))).left,
      closeTo(24, 0.01),
    );
    expect(find.byKey(readerPageBodyKey(2, 1)), findsNothing);
  });

  testWidgets('屏幕放不下两栏时退回单栏', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, count: 20, dualPage: true);

    expect(find.byKey(readerPageBodyKey(2, 0)), findsOneWidget);
    expect(find.byKey(readerPageBodyKey(2, 1)), findsNothing);
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
