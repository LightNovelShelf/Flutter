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

import 'support/reader_screen.dart';

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

/// 整页插图正好占满一栏，用它按栏数造章：栏数完全可控，不受字体度量影响。
List<NovelReaderBlock> _pageBlocks(int columns) => normalizeNovelBlocks(
  List<String>.generate(
    columns,
    (index) =>
        '<div class="illus duokan-image-single">'
        '<img src="https://img.example/p$index.webp?size=1000x2000"/></div>',
  ).join(),
);

/// 占 [columns] 栏的一章。
ReaderChapterContent _paged(int sortNum, int columns) => ReaderChapterContent(
  sortNum: sortNum,
  blocks: _pageBlocks(columns),
  style: _style,
);

class _Harness {
  _Harness({
    required List<NovelReaderBlock> blocks,
    required this.paged,
    this.dualPage = false,
    ReaderChapterContent? previous,
    ReaderChapterContent? next,
    this.restoreLocator,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 24),
    ReaderContentStyle style = _style,
    this.sortNum = 2,
    this.totalChapters = 0,
    this.autoServe,
  }) : chapters = <ReaderChapterContent>[
         ?previous,
         ReaderChapterContent(sortNum: sortNum, blocks: blocks, style: style),
         ?next,
       ];

  /// 直接给定整段连续章节，用来摆各种栏数组合。
  _Harness.of({
    required this.chapters,
    required this.sortNum,
    required this.totalChapters,
    this.dualPage = true,
  }) : paged = true,
       padding = const EdgeInsets.fromLTRB(24, 12, 24, 24),
       autoServe = null;

  /// 模拟上层把离当前章太远的那些移出窗口。
  void retainAround(int radius) => chapters.removeWhere(
    (chapter) => (chapter.sortNum - sortNum).abs() > radius,
  );

  /// 已备好的连续章节，按章号升序。
  final List<ReaderChapterContent> chapters;
  int sortNum;
  final int totalChapters;

  /// 上层在 [ReaderContentView.onNeedChapter] 后送来的那一章，null 表示不响应。
  final ReaderChapterContent Function(int sortNum)? autoServe;

  final bool paged;
  final bool dualPage;
  String? restoreLocator;
  final EdgeInsets padding;
  int restoreToken = 0;
  Color textColor = const Color(0xFF2A2318);
  final ReaderContentController controller = ReaderContentController();
  final Set<int> failedChapters = <int>{};

  final List<ReaderContentPosition> positions = <ReaderContentPosition>[];
  final List<bool> boundaries = <bool>[];
  final List<int> needed = <int>[];
  final List<int> chapterChanges = <int>[];
  int centerTaps = 0;
  int ready = 0;

  ReaderChapterContent get chapter =>
      chapters.firstWhere((chapter) => chapter.sortNum == sortNum);
  List<NovelReaderBlock> get blocks => chapter.blocks;
  ReaderContentPosition get last => positions.last;

  set chapter(ReaderChapterContent value) =>
      chapters[chapters.indexWhere((c) => c.sortNum == value.sortNum)] = value;

  /// 模拟上层在 [ReaderContentView.onChapterChanged] 之后把当前章挪过去。
  void shiftTo(int sortNum) => this.sortNum = sortNum;

  /// 模拟上层把请求到的一章接进窗口两端。
  void join(ReaderChapterContent content) {
    if (chapters.any((c) => c.sortNum == content.sortNum)) return;
    if (content.sortNum == chapters.first.sortNum - 1) {
      chapters.insert(0, content);
    } else if (content.sortNum == chapters.last.sortNum + 1) {
      chapters.add(content);
    }
  }

  void _onNeedChapter(bool next, int fromSortNum) {
    final target = fromSortNum + (next ? 1 : -1);
    needed.add(target);
    final serve = autoServe;
    if (serve != null) join(serve(target));
  }

  Widget build() => MaterialApp(
    home: Scaffold(
      body: DefaultTextStyle.merge(
        style: TextStyle(color: textColor),
        child: ReaderContentView(
          chapters: chapters,
          sortNum: sortNum,
          totalChapters: totalChapters,
          failedChapters: failedChapters,
          paged: paged,
          dualPage: dualPage,
          padding: padding,
          restoreLocator: restoreLocator,
          restoreProgression: 0,
          restoreToken: restoreToken,
          onPosition: positions.add,
          onTapCenter: () => centerTaps++,
          onChapterChanged: chapterChanges.add,
          onBoundary: boundaries.add,
          onNeedChapter: _onNeedChapter,
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
  int totalChapters = 0,
  ReaderChapterContent? previous,
  ReaderChapterContent? next,
  ReaderChapterContent Function(int sortNum)? autoServe,
}) async {
  final harness = _Harness(
    blocks: _blocks(count),
    paged: paged,
    dualPage: dualPage,
    previous: previous,
    next: next,
    restoreLocator: restoreLocator,
    totalChapters: totalChapters,
    autoServe: autoServe,
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

/// 屏首那一栏：视口内最靠左的正文栏，返回 (章号, 栏下标)。
/// `PageView` 会预建左右邻屏，视口外的那些不算。
(int, int)? _headColumn(WidgetTester tester) {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  (int, int)? head;
  double? headLeft;
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'reader-page-',
                ),
          )
          .evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    if (left < 0 || left >= width) continue;
    if (headLeft != null && left >= headLeft) continue;
    headLeft = left;
    final parts = (element.widget.key! as ValueKey<String>).value.split('-');
    head = (int.parse(parts[2]), int.parse(parts[3]));
  }
  return head;
}

/// 当前屏从左到右每一栏上摆着什么，见 `support/reader_screen.dart`。
List<String> _screenSlots(WidgetTester tester, {int columns = 1}) =>
    readerScreenSlots(tester, columns: columns);

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

  /// 加载栏一直在转圈，`pumpAndSettle` 会等不到静止，只能推固定帧数。
  Future<void> spin(WidgetTester tester, [int frames = 20]) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('单页不预加载：首页再往前翻先转圈请求上一章，中间点击只切工具栏', (tester) async {
    final harness = await _pump(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tapAt(const Offset(100, 300));
    await spin(tester);

    // 上一章还没备好：这一屏摆加载栏，并请求第 1 章。
    expect(harness.needed, <int>[1]);
    expect(harness.boundaries, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_pageText('第0段'), findsNothing);

    // 章节接进来后落在上一章末栏。
    harness.join(_chapter(1, count: 12));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.last.sortNum, 1);
    expect(harness.last.page, harness.last.pages);
    expect(harness.chapterChanges, <int>[1]);

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(harness.centerTaps, 1);
  });

  testWidgets('单页不预加载：末页再往后翻先转圈请求下一章，到位后显示章首', (tester) async {
    final harness = await _pump(tester, count: 12);

    expect(harness.last.pages, greaterThan(1));
    while (harness.last.page < harness.last.pages) {
      final page = harness.last.page;
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
      expect(harness.last.page, page + 1);
    }
    expect(harness.last.progression, 1);
    // 读到末页为止都不该去取下一章。
    expect(harness.needed, isEmpty);

    await tester.tapAt(const Offset(700, 300));
    await spin(tester);

    expect(harness.needed, <int>[3]);
    expect(harness.boundaries, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    harness.join(_chapter(3, count: 12));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_pageText('第3章第0段'), findsWidgets);
    expect(harness.last.sortNum, 3);
    expect(harness.last.page, 1);
    expect(harness.chapterChanges, <int>[3]);
  });

  testWidgets('全书末章之后不再摆加载栏，也不请求', (tester) async {
    final harness = await _pump(tester, count: 12, totalChapters: 2);

    while (harness.last.page < harness.last.pages) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
    }
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(harness.needed, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 条外没有栏可翻，仍交给上层，上层会发现没有下一章。
    expect(harness.boundaries, <bool>[true]);
  });

  testWidgets('单页不预加载：逐栏翻到章尾，再翻才转圈，取回来接着往下读', (tester) async {
    // 第 2 章两栏，全书 3 章。屏应当是 <2上>、<2下>、<转圈>、<3>。
    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[_paged(2, 2)],
      sortNum: 2,
      totalChapters: 3,
      dualPage: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(_screenSlots(tester), <String>['2-0']);
    expect((harness.last.sortNum, harness.last.page), (2, 1));
    expect(harness.needed, isEmpty);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester), <String>['2-1']);
    expect((harness.last.sortNum, harness.last.page), (2, 2));
    expect(harness.needed, isEmpty);

    await tester.tapAt(const Offset(700, 300));
    await spin(tester);
    expect(_screenSlots(tester), <String>['…']);
    expect(harness.needed, <int>[3]);
    // 位置仍记在章尾那一栏上，等章节到位再挪。
    expect((harness.last.sortNum, harness.last.page), (2, 2));

    harness.join(_paged(3, 2));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(_screenSlots(tester), <String>['3-0']);
    expect((harness.last.sortNum, harness.last.page), (3, 1));
    expect(harness.chapterChanges, <int>[3]);
  });

  testWidgets('单页预加载：下一章已备好，跨章那一下不出加载栏', (tester) async {
    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[_paged(2, 1), _paged(3, 2)],
      sortNum: 2,
      totalChapters: 3,
      dualPage: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(_screenSlots(tester), <String>['2-0']);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(_screenSlots(tester), <String>['3-0']);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect((harness.last.sortNum, harness.last.page), (3, 1));
    expect(harness.chapterChanges, <int>[3]);
  });

  testWidgets('全书首章往前翻：不转圈也不请求', (tester) async {
    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[_paged(1, 2)],
      sortNum: 1,
      totalChapters: 3,
      dualPage: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();

    expect(_screenSlots(tester), <String>['1-0']);
    expect(harness.needed, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.boundaries, <bool>[false]);
  });

  testWidgets('取章失败后加载栏改成重试块，点一下重新请求', (tester) async {
    final harness = await _pump(tester, count: 12);

    while (harness.last.page < harness.last.pages) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
    }
    await tester.tapAt(const Offset(700, 300));
    await spin(tester);
    expect(harness.needed, <int>[3]);

    harness.failedChapters.add(3);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('加载失败，点击重试'));
    await tester.pumpAndSettle();

    expect(harness.needed, <int>[3, 3]);
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
    expect(harness.chapterChanges, <int>[3]);
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
    expect(harness.chapterChanges, <int>[3]);
    expect(harness.last.sortNum, 3);
    expect(harness.last.page, 1);
  });

  testWidgets('首页再往前翻进上一章：落在上一章末页', (tester) async {
    final harness = await _pump(tester, count: 12, previous: _chapter(1));
    expect(harness.last.page, 1);

    await tester.tapAt(const Offset(100, 300));
    await tester.pumpAndSettle();

    expect(harness.boundaries, isEmpty);
    expect(harness.chapterChanges, <int>[1]);
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

    harness.join(_chapter(1));
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
    expect(harness.chapterChanges, <int>[1]);
    expect(harness.last.sortNum, 1);
  });

  testWidgets('整页插图缩进一页，不再被分页切成两半', (tester) async {
    final harness = _Harness(
      blocks: normalizeNovelBlocks(
        '<div class="illus duokan-image-single">'
        '<img src="https://img.example/cover.webp?size=1000x2000"/></div>'
        '<p>图后的正文</p>',
      ),
      paged: true,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 插图独占一页，正文另起一页：中间不再夹着只剩一条图的碎片页。
    expect(harness.last.pages, 2);

    final page = tester.getRect(find.byKey(readerPageBodyKey(2, 0)));
    final image = tester.getRect(find.byType(BookImage).first);
    expect(image.top, page.top);
    // 图连同下方的 6px 间距一起装进这一页。
    expect(image.height, closeTo(page.height - 6, 0.01));
    // 等比缩窄，并且居中摆放。
    expect(image.width / image.height, closeTo(0.5, 0.01));
    expect(image.center.dx, closeTo(page.center.dx, 0.5));
  });

  /// 10 寸安卓平板横屏：1280x800 逻辑像素。双页只在这个量级的屏幕上才开。
  void useTabletLandscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('双页模式：两栏并排半屏，一屏摆连续的两栏', (tester) async {
    useTabletLandscape(tester);

    // 单栏跑一遍同样栏宽的正文（左右留白 340 => 正文 600），拿到栏数。
    // 翻页条按栏走，双页只改一屏摆几栏，栏数应当一致。
    final narrow = _Harness(
      blocks: _blocks(40),
      paged: true,
      padding: const EdgeInsets.fromLTRB(340, 12, 340, 24),
    );
    await tester.pumpWidget(narrow.build());
    await tester.pumpAndSettle();
    final columns = narrow.last.pages;
    expect(columns, greaterThan(2));

    final harness = await _pump(tester, count: 40, dualPage: true);

    // 上报的仍是栏（页），不是屏：换成单栏读同一处时页码对得上。
    expect(harness.last.pages, columns);
    expect(harness.last.page, 1);

    // 左右两栏各占半屏：外侧照旧留白，内侧各让出一半栏间距。
    final left = tester.getRect(find.byKey(readerPageBodyKey(2, 0)));
    final right = tester.getRect(find.byKey(readerPageBodyKey(2, 1)));
    expect(left.left, closeTo(24, 0.01));
    expect(left.width, closeTo(600, 0.01));
    expect(right.left, closeTo(656, 0.01));
    expect(right.width, closeTo(600, 0.01));
    expect(find.byKey(readerPageBodyKey(2, 2)), findsNothing);

    // 翻一屏走两栏。
    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();

    expect(harness.last.page, 3);
    expect(
      tester.getRect(find.byKey(readerPageBodyKey(2, 2))).left,
      closeTo(24, 0.01),
    );
    expect(find.byKey(readerPageBodyKey(2, 1)), findsNothing);
  });

  testWidgets('双页模式：只有一栏的章节，右栏接下一章而不是留空', (tester) async {
    useTabletLandscape(tester);

    // 整页插图的章节只占一栏。屏按栏切，右栏该接上已预渲染的下一章。
    final harness = _Harness(
      blocks: normalizeNovelBlocks(
        '<div class="illus duokan-image-single">'
        '<img src="https://img.example/only.webp?size=1000x2000"/></div>',
      ),
      paged: true,
      dualPage: true,
      next: _chapter(3, count: 12),
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 本章只有一栏，位置仍记在本章第一栏上。
    expect(harness.last.sortNum, 2);
    expect(harness.last.pages, 1);
    expect(harness.last.page, 1);

    // 左栏是插图所在的本章唯一一栏，右栏是下一章的第一栏。
    final left = find.byKey(readerPageBodyKey(2, 0));
    final right = find.byKey(readerPageBodyKey(3, 0));
    expect(left, findsOneWidget);
    expect(right, findsOneWidget);
    expect(tester.getRect(left).left, closeTo(24, 0.01));
    expect(tester.getRect(right).left, closeTo(656, 0.01));
    expect(
      find.descendant(of: left, matching: find.byType(BookImage)),
      findsOneWidget,
    );
    expect(_pageText('第3章第0段'), findsWidgets);
  });

  /// 只占一栏的整页插图章。
  List<NovelReaderBlock> illustration() => normalizeNovelBlocks(
    '<div class="illus duokan-image-single">'
    '<img src="https://img.example/only.webp?size=1000x2000"/></div>',
  );

  ReaderChapterContent illustrated(int sortNum) => ReaderChapterContent(
    sortNum: sortNum,
    blocks: illustration(),
    style: _style,
  );

  /// 转圈那一栏的中心横坐标。
  double spinnerX(WidgetTester tester) =>
      tester.getRect(find.byType(CircularProgressIndicator)).center.dx;

  /// 上报的位置必须就是屏首那一栏。
  void expectHeadReported(WidgetTester tester, _Harness harness) {
    expect(_headColumn(tester), (harness.last.sortNum, harness.last.page - 1));
  }

  testWidgets('双页不预加载：右栏空着就转圈请求下一章，到位后右栏摆下一章', (tester) async {
    useTabletLandscape(tester);

    final harness = _Harness(
      blocks: illustration(),
      paged: true,
      dualPage: true,
    );
    await tester.pumpWidget(harness.build());
    await spin(tester);

    // 本章只有一栏，右栏没内容：右栏转圈并请求下一章，位置仍记在本章唯一那一栏上。
    expect(harness.last.sortNum, 2);
    expect(harness.last.page, 1);
    expect(harness.needed, <int>[3]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(spinnerX(tester), greaterThan(640));

    // 同一章不重复请求。
    await spin(tester, 40);
    expect(harness.needed, <int>[3]);

    harness.join(_chapter(3, count: 12));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(readerPageBodyKey(2, 0)), findsOneWidget);
    expect(find.byKey(readerPageBodyKey(3, 0)), findsOneWidget);
    expect(_pageText('第3章第0段'), findsWidgets);
    // 右栏是下一章，页码与进度按屏首那一栏算，所以当前章没变。
    expect(harness.last.sortNum, 2);
    expect(harness.chapterChanges, isEmpty);
    expectHeadReported(tester, harness);
  });

  testWidgets('双页乐观翻页：整屏空白左栏转圈，接进来的章只有一栏就换右栏接着转', (tester) async {
    useTabletLandscape(tester);

    // 两章各只有一栏，一屏正好摆满，再往后翻整屏都是空的。
    final harness = _Harness(
      blocks: illustration(),
      paged: true,
      dualPage: true,
      next: illustrated(3),
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    // 下一章还没排完时右栏也会摆加载栏并请求，上层发现已在窗口里即无事发生。
    expect(harness.needed, <int>[3]);
    harness.needed.clear();

    await tester.tapAt(const Offset(1100, 400));
    await spin(tester);

    // 两栏都空：左栏转圈，请求第 4 章。
    expect(harness.needed, <int>[4]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(spinnerX(tester), lessThan(640));

    harness.join(illustrated(4));
    await tester.pumpWidget(harness.build());
    await spin(tester);

    // 第 4 章只有一栏，落在左栏；右栏还是空的，改成右栏转圈并请求第 5 章。
    expect(harness.last.sortNum, 4);
    expect(harness.chapterChanges, <int>[4]);
    expect(find.byKey(readerPageBodyKey(4, 0)), findsOneWidget);
    expectHeadReported(tester, harness);
    expect(harness.needed, <int>[4, 5]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(spinnerX(tester), greaterThan(640));
  });

  testWidgets('双页往前翻：整屏加载栏时右栏转圈，接进来后落在上一章末栏', (tester) async {
    useTabletLandscape(tester);

    final harness = _Harness(blocks: _blocks(40), paged: true, dualPage: true);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(harness.needed, isEmpty);

    await tester.tapAt(const Offset(100, 400));
    await spin(tester);

    // 条前的加载栏补满一屏，转圈的是紧挨着正文的右栏。
    expect(harness.needed, <int>[1]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(spinnerX(tester), greaterThan(640));

    harness.join(_chapter(1, count: 12));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.last.sortNum, 1);
    // 落在上一章末尾那一屏：屏首可能是倒数第二栏，进度到不了 100%。
    expect(harness.last.page, greaterThanOrEqualTo(harness.last.pages - 1));
    expect(harness.chapterChanges, <int>[1]);
    expectHeadReported(tester, harness);
  });

  testWidgets('双页：上一章半路接进来，屏上那两栏不重新配对', (tester) async {
    useTabletLandscape(tester);

    // 第 3 章只占一栏，右栏先是加载栏。
    final harness = _Harness(
      blocks: illustration(),
      paged: true,
      dualPage: true,
      sortNum: 3,
    );
    await tester.pumpWidget(harness.build());
    await spin(tester);
    expect(_screenSlots(tester, columns: 2), <String>['3-0', '…']);

    // 前后两章一起接进来：条整体前移，但屏首仍是第 3 章那一栏，右栏换成第 4 章。
    harness
      ..join(illustrated(2))
      ..join(_paged(4, 2));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(_screenSlots(tester, columns: 2), <String>['3-0', '4-0']);
    expect(harness.last.sortNum, 3);
    expect(harness.last.page, 1);
    expect(harness.chapterChanges, isEmpty);
    expectHeadReported(tester, harness);
  });

  testWidgets('双页翻页顺序：栏首尾相接，一屏摆连续两栏，末章之后留白', (tester) async {
    useTabletLandscape(tester);

    // 全书 4 章，栏数 1、1、1、2：屏应当是 <1,2>、<3,4上>、<4下,空>。
    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[
        _paged(1, 1),
        _paged(2, 1),
        _paged(3, 1),
        _paged(4, 2),
      ],
      sortNum: 1,
      totalChapters: 4,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(_screenSlots(tester, columns: 2), <String>['1-0', '2-0']);
    expect((harness.last.sortNum, harness.last.page), (1, 1));
    // 第 2 章还没排完版那几帧右栏是加载栏，会请求一次；上层发现已在窗口里即无事发生。
    expect(harness.needed, <int>[2]);
    harness.needed.clear();

    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['3-0', '4-0']);
    expect((harness.last.sortNum, harness.last.page), (3, 1));

    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['4-1', '']);
    expect((harness.last.sortNum, harness.last.page), (4, 2));
    // 全书到头，末章之后不再请求。
    expect(harness.needed, isEmpty);

    // 原路翻回去，每一屏都还是原来那两栏。
    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['3-0', '4-0']);

    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['1-0', '2-0']);
    expect((harness.last.sortNum, harness.last.page), (1, 1));
  });

  testWidgets('双页：读到的章被移出窗口，当前屏那两栏一动不动', (tester) async {
    useTabletLandscape(tester);

    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[
        _paged(1, 1),
        _paged(2, 1),
        _paged(3, 1),
        _paged(4, 2),
      ],
      sortNum: 1,
      totalChapters: 6,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1100, 400));
    await spin(tester);
    expect(_screenSlots(tester, columns: 2), <String>['4-1', '…']);
    harness.shiftTo(4);

    // 上层按当前章收拢窗口丢掉第 1 章，同时把预备好的第 5 章接进来：
    // 条的两端一起变，屏上那两栏不许跟着重新配对。
    harness
      ..retainAround(2)
      ..join(_paged(5, 1));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(harness.chapters.map((chapter) => chapter.sortNum), <int>[
      2,
      3,
      4,
      5,
    ]);
    expect(_screenSlots(tester, columns: 2), <String>['4-1', '5-0']);
    expect((harness.last.sortNum, harness.last.page), (4, 2));
    expectHeadReported(tester, harness);
  });

  testWidgets('双页翻页顺序：多栏章夹着单栏章，屏按栏切不按章切', (tester) async {
    useTabletLandscape(tester);

    // 栏数 2、1、2：屏应当是 <1上,1下>、<2,3上>、<3下,空>。
    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[
        _paged(1, 2),
        _paged(2, 1),
        _paged(3, 2),
      ],
      sortNum: 1,
      totalChapters: 3,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['1-0', '1-1']);
    expect((harness.last.sortNum, harness.last.page), (1, 1));

    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['2-0', '3-0']);
    expect((harness.last.sortNum, harness.last.page), (2, 1));
    expect(harness.chapterChanges, <int>[2]);

    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['3-1', '']);
    expect((harness.last.sortNum, harness.last.page), (3, 2));
    expect(harness.chapterChanges, <int>[2, 3]);
    expect(harness.needed, isEmpty);
  });

  testWidgets('双页往前翻到条外：右栏转圈，左栏留白', (tester) async {
    useTabletLandscape(tester);

    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[_paged(2, 2)],
      sortNum: 2,
      totalChapters: 4,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['2-0', '2-1']);

    await tester.tapAt(const Offset(100, 400));
    await spin(tester);

    // 加载栏只在紧挨着翻页条的右栏上转，左栏留白。
    expect(_screenSlots(tester, columns: 2), <String>['', '…']);
    expect(harness.needed, <int>[1]);

    harness.join(_paged(1, 2));
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 落到上一章末尾那一屏：这里是全书首章，它的两栏正好凑成一屏，
    // 位置按屏首算，记在第 0 栏上。
    expect(_screenSlots(tester, columns: 2), <String>['1-0', '1-1']);
    expect((harness.last.sortNum, harness.last.page), (1, 1));
    expect(harness.chapterChanges, <int>[1]);
  });

  testWidgets('双页转单页：位置留在原来那一栏上', (tester) async {
    useTabletLandscape(tester);

    final harness = _Harness.of(
      chapters: <ReaderChapterContent>[
        _paged(1, 2),
        _paged(2, 1),
        _paged(3, 2),
      ],
      sortNum: 1,
      totalChapters: 3,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1100, 400));
    await tester.pumpAndSettle();
    expect(_screenSlots(tester, columns: 2), <String>['2-0', '3-0']);

    // 转成竖屏手机：不再分栏，屏上只剩原来的屏首那一栏。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(_screenSlots(tester), <String>['2-0']);
    expect(harness.last.sortNum, 2);
    expect(harness.last.page, 1);
  });

  testWidgets('双页读全书末章：右栏空着也不转圈，后面没有章可等', (tester) async {
    useTabletLandscape(tester);

    // 全书 4 章，末章只占一栏：右半屏空着，但已经没有下一章了。
    final harness = _Harness(
      blocks: illustration(),
      paged: true,
      dualPage: true,
      sortNum: 4,
      totalChapters: 4,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    expect(find.byKey(readerPageBodyKey(4, 0)), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.needed, isEmpty);

    // 往前翻仍要转圈：上一章是有的。
    await tester.tapAt(const Offset(100, 400));
    await spin(tester);
    expect(harness.needed, <int>[3]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('横放的手机不分栏：栏太矮', (tester) async {
    // Pixel 8 横屏：800x360 逻辑像素，宽度够但高度落在 height-compact 里。
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pump(tester, count: 20, dualPage: true);

    expect(find.byKey(readerPageBodyKey(2, 0)), findsOneWidget);
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
