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

/// 动态切换图片预览手势，不重载正文，避免阅读位置丢失。
String readerImagePreviewModeScript(bool openOnLongPress) =>
    '(function(){if(window.__nvSetLongPressPreview)'
    'window.__nvSetLongPressPreview($openOnLongPress);})();';

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
  required String readerCssSource,
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
    'body{font-family:$fontFamily}',
    readerCssSource,
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
