/// 正文标记与渲染器之间的约定。CSS/JS 时代由 WebView 兜着的两件事现在必须落到标记里：
/// 脚注锚点走私有 scheme 才能和普通外链区分开，段首缩进得是元素占位而不是空白
/// （两端对齐会把空白拉伸）。生成这两样标记的是各正文来源自己的加工层，这里只放约定。
library;

/// 脚注锚点的私有 scheme：`onTapUrl` 靠它把正文链接与脚注区分开。
const String readerFootnoteScheme = 'lnfootnote';

/// HtmlWidget 渲染的固定 2em 首行占位元素。
const String readerIndentElement = 'reader-indent';

/// 非脚注链接返回 null，交给调用方按外链处理（阅读器内一律不跳转）。
String? readerFootnoteIdFromUrl(String url) {
  const prefix = '$readerFootnoteScheme:';
  if (!url.startsWith(prefix)) return null;
  final id = url.substring(prefix.length);
  return id.isEmpty ? null : Uri.decodeComponent(id);
}
