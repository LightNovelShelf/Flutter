import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_pagination.dart';

/// 行顶 + 块底构成的候选断点表：`step` 是行高，`count` 是行数。
List<double> _lineBreaks(double step, int count) => <double>[
  for (var i = 1; i <= count; i++) step * i,
];

void main() {
  group('双页分栏', () {
    int columns(double width, double height, {double fontSize = 18}) =>
        readerColumnCount(
          dualPage: true,
          width: width,
          height: height,
          fontSize: fontSize,
        );

    test('关掉时无论多宽都是单栏', () {
      expect(
        readerColumnCount(
          dualPage: false,
          width: 2000,
          height: 1400,
          fontSize: 18,
        ),
        1,
      );
    });

    test('横放的手机不分栏：栏太矮，一屏只剩十来行', () {
      // Pixel 8 横屏的正文区。宽度够，但高度落在 height-compact 里。
      expect(columns(752, 324), 1);
    });

    test('竖持不分栏', () {
      expect(columns(312, 764), 1); // 手机竖屏
      expect(columns(772, 1120), 1); // 平板竖屏：宽度够，宽高比不够
    });

    test('平板横屏分两栏', () {
      expect(columns(1232, 740), 2); // 10 寸平板
      expect(columns(1132, 760), 2); // 11 寸 iPad
    });

    test('字号调大到一栏放不下 25 字就退回单栏', () {
      expect(columns(1132, 760, fontSize: 18), 2);
      expect(columns(1132, 760, fontSize: 26), 1);
    });
  });

  group('固定版式分屏', () {
    bool spread(double width, double height) =>
        readerFixedLayoutSpread(dualPage: true, width: width, height: height);

    test('漫画只看方向：横屏就分屏，跟字号与高度无关', () {
      expect(spread(800, 360), isTrue); // 横放的手机也分
      expect(spread(1280, 800), isTrue);
      expect(spread(360, 800), isFalse); // 竖屏不分
    });

    test('关掉时不分屏', () {
      expect(
        readerFixedLayoutSpread(dualPage: false, width: 1280, height: 800),
        isFalse,
      );
    });
  });

  group('翻页切分', () {
    test('断点恰好落在行顶时按视口整页切', () {
      expect(
        paginateReaderContent(
          contentHeight: 300,
          pageHeight: 100,
          breaks: _lineBreaks(20, 15),
        ),
        <double>[0, 100, 200],
      );
    });

    test('断点稀疏时提前换页，不把整块劈开', () {
      expect(
        paginateReaderContent(
          contentHeight: 300,
          pageHeight: 100,
          breaks: const <double>[60, 120, 180, 240, 300],
        ),
        <double>[0, 60, 120, 180, 240],
      );
    });

    test('超高原子（整页插图）无可断处时硬切', () {
      expect(
        paginateReaderContent(
          contentHeight: 250,
          pageHeight: 100,
          breaks: const <double>[250],
        ),
        <double>[0, 100, 200],
      );
    });

    test('测量误差在容差内不额外多切一页', () {
      expect(
        paginateReaderContent(
          contentHeight: 100.4,
          pageHeight: 100,
          breaks: const <double>[20.1, 40.2, 60.3, 80.35, 100.4],
        ),
        <double>[0],
      );
    });

    test('页顶严格递增且每页不超过视口', () {
      const pageHeight = 640.0;
      const lineHeight = 21.3;
      final breaks = _lineBreaks(lineHeight, 120);
      final pageTops = paginateReaderContent(
        contentHeight: lineHeight * 120,
        pageHeight: pageHeight,
        breaks: breaks,
      );
      expect(pageTops.first, 0);
      expect(pageTops.length, greaterThan(1));
      for (var i = 1; i < pageTops.length; i++) {
        expect(pageTops[i], greaterThan(pageTops[i - 1]));
        expect(
          pageTops[i] - pageTops[i - 1],
          lessThanOrEqualTo(pageHeight + 0.5),
        );
      }
    });

    test('内容不足一页或尺寸未测出时只有一页', () {
      expect(
        paginateReaderContent(
          contentHeight: 80,
          pageHeight: 100,
          breaks: const <double>[20, 40, 60, 80],
        ),
        <double>[0],
      );
      expect(
        paginateReaderContent(
          contentHeight: 0,
          pageHeight: 100,
          breaks: const <double>[],
        ),
        <double>[0],
      );
      expect(
        paginateReaderContent(
          contentHeight: 300,
          pageHeight: 0,
          breaks: const <double>[100, 200, 300],
        ),
        <double>[0],
      );
      expect(
        paginateReaderContent(
          contentHeight: 100,
          pageHeight: 100,
          breaks: const <double>[],
        ),
        <double>[0],
      );
    });
  });

  group('偏移定位', () {
    const pageTops = <double>[0, 100, 200];

    test('页下标越界收敛到首/末页', () {
      expect(readerPageIndexForOffset(pageTops, -50), 0);
      expect(readerPageIndexForOffset(pageTops, 0), 0);
      expect(readerPageIndexForOffset(pageTops, 99), 0);
      expect(readerPageIndexForOffset(pageTops, 100), 1);
      expect(readerPageIndexForOffset(pageTops, 199.6), 2);
      expect(readerPageIndexForOffset(pageTops, 5000), 2);
      expect(readerPageIndexForOffset(const <double>[], 120), 0);
    });

    test('块下标：缝隙取下一块，末尾夹住最后一块', () {
      const tops = <double>[0, 60, 130];
      const bottoms = <double>[50, 120, 190];
      int at(double offset) => readerBlockIndexAtOffset(
        blockTops: tops,
        blockBottoms: bottoms,
        offset: offset,
      );

      expect(at(-20), 0);
      expect(at(0), 0);
      expect(at(49), 0);
      expect(at(50), 1);
      expect(at(55), 1);
      expect(at(125), 2);
      expect(at(189), 2);
      expect(at(500), 2);
    });

    test('块表为空时回到首块', () {
      expect(
        readerBlockIndexAtOffset(
          blockTops: const <double>[],
          blockBottoms: const <double>[],
          offset: 300,
        ),
        0,
      );
    });
  });

  group('进度块定位', () {
    const tops = <double>[0, 60, 130];
    const bottoms = <double>[50, 120, 190];
    int locate(double offset, {required bool paged, double pageHeight = 100}) =>
        readerLocatorBlockIndex(
          blockTops: tops,
          blockBottoms: bottoms,
          offset: offset,
          paged: paged,
          pageHeight: pageHeight,
        );

    test('滚动模式取偏移处的块', () {
      expect(locate(0, paged: false), 0);
      expect(locate(30, paged: false), 0);
      expect(locate(55, paged: false), 1);
      expect(locate(500, paged: false), 2);
    });

    test('翻页模式跳过跨自上一页的块', () {
      // 块 1 覆盖 60..120，跨过页顶 100。
      expect(locate(100, paged: false), 1);
      expect(locate(100, paged: true), 2);
    });

    test('偏移正好落在块顶时算本页的块', () {
      expect(locate(60, paged: true), 1);
      expect(locate(130, paged: true), 2);
    });

    test('本页放不下整块时仍取跨页的那个块', () {
      expect(locate(100, paged: true, pageHeight: 20), 1);
      expect(locate(500, paged: true), 2);
    });
  });

  group('跨章翻页条', () {
    final strip = ReaderPageStrip<String>.of(
      <String>['上一章', '本章', '下一章'],
      (chapter) => switch (chapter) {
        '上一章' => 2,
        '本章' => 3,
        _ => 4,
      },
    );

    test('相邻章的页首尾相接', () {
      expect(strip.pages, 9);
      expect(strip.globalPageOf('上一章', 0), 0);
      expect(strip.globalPageOf('本章', 0), 2);
      expect(strip.globalPageOf('下一章', 0), 5);
    });

    test('全局页序反查回章内页码', () {
      expect(strip.locate(1), ('上一章', 1));
      expect(strip.locate(2), ('本章', 0));
      expect(strip.locate(4), ('本章', 2));
      expect(strip.locate(5), ('下一章', 0));
      expect(strip.locate(8), ('下一章', 3));
    });

    test('越界与空条不给出页', () {
      expect(strip.locate(9), isNull);
      expect(strip.locate(-1), isNull);
      const empty = ReaderPageStrip<String>.empty();
      expect(empty.pages, 0);
      expect(empty.isEmpty, isTrue);
      expect(empty.locate(0), isNull);
      // 未接入条的章按单章处理，页码原样返回。
      expect(empty.globalPageOf('本章', 2), 2);
    });
  });
}
