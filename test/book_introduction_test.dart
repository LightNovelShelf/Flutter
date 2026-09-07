import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/features/book/widgets/book_introduction.dart';
import 'package:lightnovel/shared/widgets/fade_clamp_box.dart';
import 'package:lightnovel/shared/widgets/html_content.dart';

/// 折叠预算是五行紧凑行高，跟简介里有没有 ruby、着重号无关。
const double _collapsedHeight = HtmlContent.compactFontSize * 1.3 * 5;

BookDetail _detail(String introduction) => BookDetail(
  seriesTitle: '',
  series: const <BookSeriesItem>[],
  id: 1,
  type: BookType.novel,
  coverUrl: '',
  coverPlaceholder: null,
  title: '书',
  authorName: null,
  category: null,
  introduction: introduction,
  lastUpdatedChapter: null,
  lastUpdatedAt: DateTime.utc(2026),
  createdAt: DateTime.utc(2026),
  favoriteCount: 0,
  viewCount: 0,
  canEdit: false,
  chapters: const <BookChapter>[],
  user: null,
  classification: BookClassification.empty,
  readPosition: null,
);

Future<void> _pump(WidgetTester tester, String introduction) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          child: BookIntroduction(detail: _detail(introduction)),
        ),
      ),
    ),
  );
  // 真实高度在布局后的帧末回调，「展开」要下一帧才出现。
  await tester.pump();
}

void main() {
  testWidgets('带 ruby 的长简介折叠到五行并给出展开', (tester) async {
    await _pump(
      tester,
      '<div><p>第一行</p><p>第二行</p><p>第三行</p><p>第四行</p><p>第五行</p>'
          '<p>情色尺度爆表的<ruby>人类复兴<rt>后宫</rt></ruby>奇幻小说</p></div>',
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FadeClampBox)).height,
      closeTo(_collapsedHeight, 0.1),
    );
    expect(find.text('展开'), findsOneWidget);
  });

  testWidgets('短简介完整显示且没有展开', (tester) async {
    await _pump(tester, '<div><p>一句话简介</p></div>');

    final height = tester.getSize(find.byType(FadeClampBox)).height;
    expect(height, lessThan(_collapsedHeight));
    expect(find.text('展开'), findsNothing);
  });
}
