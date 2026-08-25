import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'image_preview.dart';

final RegExp _scriptOrStyle = RegExp(
  r'<(script|style)[^>]*>[\s\S]*?<\/\1>',
  caseSensitive: false,
);
final RegExp _imageTag = RegExp(r'<img[^>]*>', caseSensitive: false);
final RegExp _linkedImage = RegExp(
  r'''<a\b[^>]*\bhref\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)[^>]*>\s*(<img\b[^>]*>)\s*</a>''',
  caseSensitive: false,
);
final RegExp _rubyTag = RegExp(r'<ruby[\s>]', caseSensitive: false);

/// 紧凑内容保留块级排版，只移除折叠区域不显示的内容。
String createCompactHtmlSource(String html) {
  final content = html.replaceAll(_scriptOrStyle, '').replaceAll(_imageTag, '');
  return '<div class="html-compact-root">$content</div>';
}

/// 带 ruby 注音的内容不能按固定行高裁剪。
bool htmlHasRuby(String html) => _rubyTag.hasMatch(html);

typedef HtmlSourceTransformer = String Function(String html);

/// 外层为 [HtmlContent] 注入的样式和渲染 Hook。
@immutable
class HtmlContentThemeData {
  const HtmlContentThemeData({
    this.textStyle,
    this.linkColor,
    this.sourceTransformer,
    this.stylesBuilder,
    this.widgetBuilder,
    this.onTapImage,
    this.onTapUrl,
    this.onErrorBuilder,
    this.onLoadingBuilder,
    this.baseUrl,
    this.factoryBuilder,
    this.renderMode,
    this.buildAsync,
    this.enableCaching,
    this.removeImageLinks,
    this.enableDefaultTextStyle,
    this.enableDefaultStyles,
    this.enableDefaultImagePreview,
    this.enableDefaultUrlLauncher,
    this.enableDefaultErrorBuilder,
    this.enableDefaultLoadingBuilder,
    this.rebuildTriggers,
  });

  final TextStyle? textStyle;
  final Color? linkColor;
  final HtmlSourceTransformer? sourceTransformer;
  final CustomStylesBuilder? stylesBuilder;
  final CustomWidgetBuilder? widgetBuilder;
  final void Function(ImageMetadata metadata)? onTapImage;
  final FutureOr<bool> Function(String url)? onTapUrl;
  final OnErrorBuilder? onErrorBuilder;
  final OnLoadingBuilder? onLoadingBuilder;
  final Uri? baseUrl;
  final WidgetFactory Function()? factoryBuilder;
  final RenderMode? renderMode;
  final bool? buildAsync;
  final bool? enableCaching;
  final bool? removeImageLinks;
  final bool? enableDefaultTextStyle;
  final bool? enableDefaultStyles;
  final bool? enableDefaultImagePreview;
  final bool? enableDefaultUrlLauncher;
  final bool? enableDefaultErrorBuilder;
  final bool? enableDefaultLoadingBuilder;
  final List<Object?>? rebuildTriggers;

  HtmlContentThemeData merge(HtmlContentThemeData other) =>
      HtmlContentThemeData(
        textStyle: textStyle?.merge(other.textStyle) ?? other.textStyle,
        linkColor: other.linkColor ?? linkColor,
        sourceTransformer: other.sourceTransformer ?? sourceTransformer,
        stylesBuilder: other.stylesBuilder ?? stylesBuilder,
        widgetBuilder: other.widgetBuilder ?? widgetBuilder,
        onTapImage: other.onTapImage ?? onTapImage,
        onTapUrl: other.onTapUrl ?? onTapUrl,
        onErrorBuilder: other.onErrorBuilder ?? onErrorBuilder,
        onLoadingBuilder: other.onLoadingBuilder ?? onLoadingBuilder,
        baseUrl: other.baseUrl ?? baseUrl,
        factoryBuilder: other.factoryBuilder ?? factoryBuilder,
        renderMode: other.renderMode ?? renderMode,
        buildAsync: other.buildAsync ?? buildAsync,
        enableCaching: other.enableCaching ?? enableCaching,
        removeImageLinks: other.removeImageLinks ?? removeImageLinks,
        enableDefaultTextStyle:
            other.enableDefaultTextStyle ?? enableDefaultTextStyle,
        enableDefaultStyles: other.enableDefaultStyles ?? enableDefaultStyles,
        enableDefaultImagePreview:
            other.enableDefaultImagePreview ?? enableDefaultImagePreview,
        enableDefaultUrlLauncher:
            other.enableDefaultUrlLauncher ?? enableDefaultUrlLauncher,
        enableDefaultErrorBuilder:
            other.enableDefaultErrorBuilder ?? enableDefaultErrorBuilder,
        enableDefaultLoadingBuilder:
            other.enableDefaultLoadingBuilder ?? enableDefaultLoadingBuilder,
        rebuildTriggers: other.rebuildTriggers ?? rebuildTriggers,
      );
}

/// 为子树中的 [HtmlContent] 设置或合并默认配置。
class HtmlContentTheme extends StatelessWidget {
  const HtmlContentTheme({super.key, required this.data, required this.child})
    : _merge = false;

  const HtmlContentTheme.merge({
    super.key,
    required this.data,
    required this.child,
  }) : _merge = true;

  final HtmlContentThemeData data;
  final Widget child;
  final bool _merge;

  static HtmlContentThemeData of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_HtmlContentThemeScope>()
          ?.data ??
      const HtmlContentThemeData();

  @override
  Widget build(BuildContext context) {
    final resolved = _merge ? of(context).merge(data) : data;
    return _HtmlContentThemeScope(data: resolved, child: child);
  }
}

class _HtmlContentThemeScope extends InheritedWidget {
  const _HtmlContentThemeScope({required this.data, required super.child});

  final HtmlContentThemeData data;

  @override
  bool updateShouldNotify(_HtmlContentThemeScope oldWidget) =>
      oldWidget.data != data;
}

enum _HtmlContentMode { standard, compact }

/// 应用 HTML 的统一渲染入口。
class HtmlContent extends StatelessWidget {
  const HtmlContent({super.key, required this.html})
    : _mode = _HtmlContentMode.standard;

  const HtmlContent.compact({super.key, required this.html})
    : _mode = _HtmlContentMode.compact;

  final String html;
  final _HtmlContentMode _mode;

  bool get _compact => _mode == _HtmlContentMode.compact;
  static const double compactFontSize = 14;
  static const double compactLineHeight = 1.3;
  static double compactLineExtentOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(compactFontSize) *
      compactLineHeight;

  static const List<double> _fontTagSizes = <double>[
    0.63,
    0.82,
    1,
    1.13,
    1.5,
    2,
    3,
  ];

  String _source(HtmlContentThemeData theme) {
    if (_compact) return createCompactHtmlSource(html);
    var source = theme.sourceTransformer?.call(html) ?? html;
    if (theme.removeImageLinks ?? true) {
      source = source.replaceAllMapped(
        _linkedImage,
        (match) => match.group(1) ?? '',
      );
    }
    return source;
  }

  Map<String, String>? _stylesFor(
    String? tag,
    Iterable<String> classes,
    Map<Object, String> attributes,
    double fontSize,
    String linkColor,
  ) {
    final styles = <String, String>{};
    switch (tag) {
      case 'p':
        styles['margin'] = _compact ? '0' : '0 0 8px 0';
      case 'div':
        styles['margin'] = _compact ? '0' : '0 0 0.5em';
      case 'h1':
        styles.addAll(_heading(1.75, _compact ? '0' : '0.2em 0 0.6em 0'));
      case 'h2':
        styles.addAll(_heading(1.5, _compact ? '0' : '0.3em 0 0.6em 0'));
      case 'h3':
        styles.addAll(_heading(1.3, _compact ? '0' : '0.4em 0 0.5em 0'));
      case 'h4':
        styles.addAll(_heading(1.15, _compact ? '0' : '0.4em 0'));
      case 'h5':
        styles.addAll(_heading(1.05, _compact ? '0' : '0.4em 0'));
      case 'h6':
        styles.addAll(_heading(1, _compact ? '0' : '0.4em 0'));
      case 'blockquote':
        styles['margin'] = _compact ? '0' : '0 0 0.75em 0';
        styles['padding-left'] = '1em';
      case 'ul':
      case 'ol':
        styles['margin'] = _compact ? '0' : '0 0 0.75em 0';
        styles['padding-left'] = '1.5em';
      case 'li':
        styles['margin-bottom'] = _compact ? '0' : '0.3em';
      case 'a':
        styles['color'] = linkColor;
        styles['text-decoration'] = 'underline';
      case 'img':
        styles['max-width'] = '100%';
      case 'table':
        styles['width'] = '100%';
        styles['margin'] = _compact ? '0' : '0 0 0.75em 0';
      case 'th':
      case 'td':
        styles['padding'] = '0.25em';
        styles['vertical-align'] = 'top';
      case 'rt':
        styles['font-size'] = '0.5em';
      case 'font':
        final size = int.tryParse(attributes['size'] ?? '');
        if (size != null && size >= 1 && size <= _fontTagSizes.length) {
          styles['font-size'] = _px(fontSize * _fontTagSizes[size - 1]);
        }
    }

    for (final className in classes) {
      switch (className) {
        case 'center':
          styles['text-align'] = 'center';
        case 'left':
          styles['text-align'] = 'left';
        case 'right':
          styles['text-align'] = 'right';
        case 'bold':
          styles['font-weight'] = 'bold';
        case 'ita':
          styles['font-style'] = 'italic';
        case 'dot':
        case 'em-dot':
          styles['text-emphasis'] = 'circle';
        case 'red':
          styles['color'] = '#D32F2F';
        case 'green':
          styles['color'] = '#2E7D32';
        case 'blue':
          styles['color'] = '#1565C0';
        case 'black':
          styles['color'] = '#000000';
        case 'white':
          styles['color'] = '#FFFFFF';
        case 'ph4':
        case 'pius1':
        case 'pius2':
          styles.addAll(_heading(1.5, _compact ? '0' : '0.5em 0 1em 0'));
        case 'illu':
        case 'illus':
        case 'duokan-image-single':
        case 'image-preview':
          styles['text-align'] = 'center';
        default:
          final scale = _emScale(className);
          if (scale != null) styles['font-size'] = _px(fontSize * scale);
      }
    }
    return styles.isEmpty ? null : styles;
  }

  static Map<String, String> _heading(double scale, String margin) =>
      <String, String>{
        'font-size': '${scale.toStringAsFixed(2)}em',
        'font-weight': 'bold',
        'line-height': '1.25',
        'margin': margin,
      };

  static String _px(double size) => '${size.toStringAsFixed(2)}px';

  static double? _emScale(String className) {
    if (className.length != 4 || !className.startsWith('em')) return null;
    final value = int.tryParse(className.substring(2));
    if (value == null || value < 5 || value > 30 || value == 10) return null;
    return value / 10;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = HtmlContentTheme.of(context);
    final baseFontSize = _compact ? compactFontSize : 16.0;
    final defaultTextStyle = TextStyle(
      fontSize: baseFontSize,
      height: _compact ? compactLineHeight : 1.5,
      color: _compact ? colors.onSurfaceVariant : colors.onSurface,
    );
    final textStyle = (theme.enableDefaultTextStyle ?? true)
        ? defaultTextStyle.merge(theme.textStyle)
        : theme.textStyle;
    final fontSize = textStyle?.fontSize ?? baseFontSize;
    final linkColor = theme.linkColor ?? colors.primary;
    final linkCss = '#${linkColor.toARGB32().toRadixString(16).substring(2)}';

    return HtmlWidget(
      _source(theme),
      baseUrl: theme.baseUrl,
      factoryBuilder: theme.factoryBuilder,
      buildAsync: theme.buildAsync,
      enableCaching: theme.enableCaching ?? true,
      rebuildTriggers: theme.rebuildTriggers,
      renderMode: theme.renderMode ?? RenderMode.column,
      textStyle: textStyle,
      customStylesBuilder: (element) {
        final defaults = (theme.enableDefaultStyles ?? true)
            ? _stylesFor(
                element.localName,
                element.classes,
                element.attributes,
                fontSize,
                linkCss,
              )
            : null;
        final extra = theme.stylesBuilder?.call(element);
        if (defaults == null) return extra;
        if (extra == null) return defaults;
        return <String, String>{...defaults, ...extra};
      },
      customWidgetBuilder: theme.widgetBuilder,
      onTapImage: _compact
          ? null
          : theme.onTapImage ??
                ((theme.enableDefaultImagePreview ?? true)
                    ? (metadata) => previewHtmlImage(context, metadata)
                    : null),
      onTapUrl:
          theme.onTapUrl ??
          ((theme.enableDefaultUrlLauncher ?? true) ? _openExternalUrl : null),
      onErrorBuilder:
          theme.onErrorBuilder ??
          ((theme.enableDefaultErrorBuilder ?? true)
              ? (context, element, error) => Text(
                  '内容无法显示。',
                  style: TextStyle(fontSize: fontSize, color: colors.error),
                )
              : null),
      onLoadingBuilder: _compact
          ? null
          : theme.onLoadingBuilder ??
                ((theme.enableDefaultLoadingBuilder ?? true)
                    ? (context, element, loadingProgress) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : null),
    );
  }
}

Future<bool> _openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return false;
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
