import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/comments/thread_reply_row.dart';
import 'package:lightnovel/shared/widgets/user_avatar.dart';

/// 社区回复与公告/书籍评论共用同一套缩进与分组线，改动任一端都得对齐这里的量。
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 360, child: child),
      ),
    ),
  ),
);

ThreadReplyRow _row({
  required bool isChild,
  List<Widget> actions = const <Widget>[],
}) => ThreadReplyRow(
  userName: '甲',
  avatarUrl: '',
  content: '正文',
  publishedAt: DateTime.now().subtract(const Duration(hours: 3)),
  isChild: isChild,
  actions: actions,
);

Border _groupBorder(WidgetTester tester) =>
    (tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(ThreadReplyGroup),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .border!
        as Border;

void main() {
  testWidgets('主楼正文与操作条缩进到头像右侧 56', (WidgetTester tester) async {
    await _pump(
      tester,
      _row(
        isChild: false,
        actions: <Widget>[const Icon(Icons.reply, key: ValueKey<String>('a'))],
      ),
    );

    final double rowX = tester.getTopLeft(find.byType(ThreadReplyRow)).dx;
    expect(tester.getTopLeft(find.text('正文')).dx - rowX, 56);
    expect(tester.getTopLeft(find.text('3 小时前')).dx - rowX, 56);
    // 操作插槽在时间戳右侧。
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('a'))).dx,
      greaterThan(tester.getTopLeft(find.text('3 小时前')).dx),
    );
  });

  testWidgets('子级正文顶格，头像收到 24', (WidgetTester tester) async {
    await _pump(tester, _row(isChild: true));

    final double rowX = tester.getTopLeft(find.byType(ThreadReplyRow)).dx;
    expect(tester.getTopLeft(find.text('正文')).dx - rowX, 0);
    expect(tester.getSize(find.byType(UserAvatar)).width, 24);
  });

  testWidgets('子级分组缩进 70：56 外边距 + 2 竖线 + 12 内边距', (WidgetTester tester) async {
    await _pump(
      tester,
      const ThreadReplyGroup(
        isChild: true,
        closesGroup: false,
        child: Text('子级'),
      ),
    );

    final double groupX = tester.getTopLeft(find.byType(ThreadReplyGroup)).dx;
    expect(tester.getTopLeft(find.text('子级')).dx - groupX, 70);
    expect(_groupBorder(tester).left.width, 2);
  });

  testWidgets('只有分组最后一行画发丝线', (WidgetTester tester) async {
    await _pump(
      tester,
      const ThreadReplyGroup(
        isChild: false,
        closesGroup: false,
        child: Text('主楼'),
      ),
    );
    expect(_groupBorder(tester).bottom.style, BorderStyle.none);

    await _pump(
      tester,
      const ThreadReplyGroup(
        isChild: false,
        closesGroup: true,
        child: Text('主楼'),
      ),
    );
    expect(_groupBorder(tester).bottom.style, BorderStyle.solid);
    expect(_groupBorder(tester).bottom.width, 0.5);
  });
}
