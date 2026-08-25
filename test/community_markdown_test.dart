import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/community/community_compose_screen.dart';

void main() {
  test('converts community Markdown to HTML', () {
    final html = buildCommunityContentHtml('正文 **加粗**\n\n> 引用');

    expect(html, contains('<p>正文 <strong>加粗</strong></p>'));
    expect(html, contains('<blockquote>'));
    expect(html, contains('<p>引用</p>'));
  });

  test('converts all Markdown heading levels to HTML', () {
    final html = buildCommunityContentHtml('# 一级标题\n\n###### 六级标题');

    expect(html, contains('<h1>一级标题</h1>'));
    expect(html, contains('<h6>六级标题</h6>'));
  });

  test('escapes raw HTML in community Markdown', () {
    final html = buildCommunityContentHtml('<script>alert("x")</script>');

    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;'));
  });

  test('counts rendered text without Markdown markers', () {
    final text = communityPlainText(
      '## 标题\n\n**加粗**和[链接](https://example.com)',
    );

    expect(text, '标题\n加粗和链接');
  });
}
