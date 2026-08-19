import 'reader_content_css.dart';
import 'reader_engine.dart';

const String readerBridgeChannel = 'ReaderBridge';

/// 章节正文文档构建。正文只能跑在 WebView 里（字体是 WOFF2，见 `ReaderFontCache`），
/// 分页交给 CSS 多列。主题/排版全走 CSS 变量，改设置只注入一小段 JS，免得重载丢位置。

final RegExp _openingTagPattern = RegExp(r'^<([a-zA-Z][\w:-]*)');
final RegExp _relativeImagePattern = RegExp(
  r'''(<img\b[^>]*\bsrc\s*=\s*)("|')(?![a-zA-Z][a-zA-Z0-9+.-]*:|#|//)([^"']*)\2''',
  caseSensitive: false,
);

String _escapeAttribute(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

/// 相对图片地址补全到 API 源站，`data:` 文档解析不了相对路径。
String rebaseReaderImages(String html, String imageBaseUrl) =>
    html.replaceAllMapped(_relativeImagePattern, (match) {
      final source = match[3]!;
      final separator = source.startsWith('/') ? '' : '/';
      return '${match[1]}${match[2]}$imageBaseUrl$separator$source${match[2]}';
    });

/// 给每个块的开标签打上 `data-nv-locator`，JS 才能把可视位置换算成服务端进度。
String _bodyMarkup(
  List<NovelReaderBlock> blocks,
  String fallbackHtml,
  String imageBaseUrl,
) {
  if (blocks.isEmpty) return rebaseReaderImages(fallbackHtml, imageBaseUrl);
  final buffer = StringBuffer();
  for (final block in blocks) {
    final locator = _escapeAttribute(block.locator);
    final html = rebaseReaderImages(block.html, imageBaseUrl);
    final opening = _openingTagPattern.firstMatch(html);
    if (opening == null) {
      buffer.write('<div data-nv-locator="$locator">$html</div>');
      continue;
    }
    buffer
      ..write(html.substring(0, opening.end))
      ..write(' data-nv-locator="$locator"')
      ..write(html.substring(opening.end));
  }
  return buffer.toString();
}

class ReaderTypography {
  const ReaderTypography({
    required this.backgroundColor,
    required this.textColor,
    required this.fontSize,
    required this.lineHeight,
    required this.sidePadding,
    required this.topPadding,
    required this.bottomPadding,
    required this.firstLineIndent,
  });

  /// `#RRGGBB` 页面底色。
  final String backgroundColor;

  /// `#RRGGBB` 正文色。
  final String textColor;
  final double fontSize;
  final double lineHeight;
  final double sidePadding;
  final double topPadding;
  final double bottomPadding;
  final bool firstLineIndent;

  String get _variables =>
      ':root{'
      '--nv-bg:$backgroundColor;'
      '--nv-fg:$textColor;'
      '--nv-font:${fontSize.toStringAsFixed(1)}px;'
      '--nv-line:${lineHeight.toStringAsFixed(2)};'
      '--nv-top:${topPadding.toStringAsFixed(1)}px;'
      '--nv-bottom:${bottomPadding.toStringAsFixed(1)}px;'
      '--nv-hpad:${sidePadding.toStringAsFixed(1)}px;'
      '--nv-indent:${firstLineIndent ? '2em' : '0'};'
      '}';
}

/// 排版变更时注入的脚本：只改 CSS 变量，阅读位置不丢。
String readerTypographyScript(ReaderTypography typography) {
  final style = <String, String>{
    '--nv-bg': typography.backgroundColor,
    '--nv-fg': typography.textColor,
    '--nv-font': '${typography.fontSize.toStringAsFixed(1)}px',
    '--nv-line': typography.lineHeight.toStringAsFixed(2),
    '--nv-top': '${typography.topPadding.toStringAsFixed(1)}px',
    '--nv-bottom': '${typography.bottomPadding.toStringAsFixed(1)}px',
    '--nv-hpad': '${typography.sidePadding.toStringAsFixed(1)}px',
    '--nv-indent': typography.firstLineIndent ? '2em' : '0',
  };
  final assignments = style.entries
      .map(
        (entry) =>
            "document.documentElement.style.setProperty('${entry.key}','${entry.value}');",
      )
      .join();
  return '(function(){$assignments'
      'if(window.__nvReflow)window.__nvReflow();})();';
}

/// 恢复阅读位置：优先按 locator 精确定位，找不到时退回百分比。
String readerRestoreScript(String? locator, double progression) {
  final target = locator == null ? 'null' : "'${_escapeJs(locator)}'";
  final ratio = progression.clamp(0.0, 1.0).toStringAsFixed(4);
  return '(function(){if(window.__nvRestore)'
      'window.__nvRestore($target,$ratio);})();';
}

String _escapeJs(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', ' ');

String buildReaderChapterDocument({
  required List<NovelReaderBlock> blocks,
  required String fallbackHtml,
  required String imageBaseUrl,
  required ReaderTypography typography,
  required bool paged,
  required String readerScriptSource,
  String? fontDataUrl,
  bool imagePreviewOnLongPress = false,
}) {
  final fontFace = fontDataUrl == null
      ? ''
      : "@font-face{font-family:'ChapterFont';font-display:block;"
            'src:url($fontDataUrl);font-style:normal;font-weight:400}';
  final fontFamily = fontDataUrl == null
      ? "'PingFang SC','Noto Sans SC',sans-serif"
      : "'ChapterFont','PingFang SC','Noto Sans SC',sans-serif";

  final layoutCss = paged
      // 多列容器放在 html 上：上下内边距会作用到每一列，放在 body 上只有首尾列生效。
      ? 'html{position:relative;width:100%;max-width:100%;height:100vh;'
            'max-height:100vh;margin:0!important;'
            'padding:var(--nv-top) 0 var(--nv-bottom)!important;box-sizing:border-box;'
            'column-width:100vw;column-gap:0;column-fill:auto;overflow-y:hidden}'
            'body{width:100%;max-width:100%;margin:0 auto!important;box-sizing:border-box;'
            'padding:0 var(--nv-hpad)}'
            'html,body{touch-action:none}'
      : 'body{padding:var(--nv-top) var(--nv-hpad) var(--nv-bottom)}';

  final css = <String>[
    typography._variables,
    'html,body{margin:0;padding:0;background:var(--nv-bg);color:var(--nv-fg)}',
    'html,body{scrollbar-width:none}'
        'html::-webkit-scrollbar,body::-webkit-scrollbar{display:none;width:0;height:0}',
    'body{font-family:$fontFamily;font-size:var(--nv-font);line-height:var(--nv-line);'
        'word-break:break-word;overflow-wrap:break-word;-webkit-text-size-adjust:100%}',
    // 段间距只由行高决定，和 Web 一致；额外的 margin 会让行高调到 1.0 也压不平。
    'p{margin:0;padding:0;text-indent:var(--nv-indent)}',
    'body>:last-child{margin-bottom:0!important}',
    // 长按图片时 Chromium 会发起原生拖拽，拖出一张半透明缩略图，必须禁掉。
    'img{max-width:100%;height:auto;-webkit-user-drag:none;user-drag:none}',
    'table{width:100%;max-width:100%;table-layout:fixed;border-collapse:collapse;margin:0 0 .8em}',
    'th,td{padding:0;vertical-align:top}',
    'td>img,th>img{display:block;width:100%;max-width:100%;height:auto}',
    'ruby rt{font-size:.5em;color:var(--nv-fg)}',
    'a{color:inherit;text-decoration:none}',
    // 点击热区遍布全屏，WebView 默认的点按高亮会在图片/链接上闪一下，
    // 让人以为点一下就能预览（实际可能要长按），一律关掉。
    '*{line-break:anywhere;-webkit-user-select:none!important;user-select:none!important;'
        '-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent}',
    // 书源类名样式排在基础排版之后：`.center`/`.m0` 之类要能盖掉 `p` 的缩进。
    readerContentCss,
    layoutCss,
  ].join();

  final script = _readerScript(
    paged: paged,
    imagePreviewOnLongPress: imagePreviewOnLongPress,
    source: readerScriptSource,
  );

  return '<!DOCTYPE html><html><head><meta charset="utf-8" />'
      '<meta name="viewport" content="width=device-width, initial-scale=1.0, '
      'maximum-scale=1.0, user-scalable=no" />'
      '<style>$fontFace$css</style>$script</head>'
      '<body>${_bodyMarkup(blocks, fallbackHtml, imageBaseUrl)}</body></html>';
}

String _readerScript({
  required bool paged,
  required bool imagePreviewOnLongPress,
  required String source,
}) {
  final flags =
      'var paged=$paged;var longPressPreview=$imagePreviewOnLongPress;';
  return '<script>(function(){$flags$source})();</script>';
}
