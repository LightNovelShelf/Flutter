/// 正文标记与渲染器之间的约定：脚注锚点用私有 scheme 与普通外链区分，段首缩进用元素占位而非空白
/// （两端对齐会拉伸空白）。标记由各正文来源的加工层生成。
library;

/// 脚注锚点的私有 scheme：`onTapUrl` 靠它把正文链接与脚注区分开。
const String readerFootnoteScheme = 'lnfootnote';

/// HtmlWidget 渲染的固定 2em 首行占位元素。
const String readerIndentElement = 'reader-indent';

/// 非脚注链接返回 null，交给调用方按外链处理。
String? readerFootnoteIdFromUrl(String url) {
  const prefix = '$readerFootnoteScheme:';
  if (!url.startsWith(prefix)) return null;
  final id = url.substring(prefix.length);
  return id.isEmpty ? null : Uri.decodeComponent(id);
}
