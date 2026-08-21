import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/image_preview.dart';

final RegExp _scriptOrStyle = RegExp(
  r'<(script|style)[^>]*>[\s\S]*?<\/\1>',
  caseSensitive: false,
);
final RegExp _imageTag = RegExp(r'<img[^>]*>', caseSensitive: false);
final RegExp _blockTag = RegExp(
  r'<\/?(?:p|div|h[1-6]|li|ol|ul|blockquote|section|article)(?:\s[^>]*)?>',
  caseSensitive: false,
);
final RegExp _repeatedBreak = RegExp(
  r'(?:\s*<br\s*\/?>\s*)+',
  caseSensitive: false,
);
final RegExp _leadingBreak = RegExp(r'^\s*<br\s*\/?>', caseSensitive: false);
final RegExp _trailingBreak = RegExp(r'<br\s*\/?>\s*$', caseSensitive: false);

/// 简介预览源：块级标签压成 `<br>`，去掉图片与脚本，折叠高度按纯文本行计算。
String createHtmlPreviewSource(String html) {
  final flattened = html
      .replaceAll(_scriptOrStyle, '')
      .replaceAll(_imageTag, '')
      .replaceAll(_blockTag, '<br>')
      .replaceAll(_repeatedBreak, '<br>')
      .replaceFirst(_leadingBreak, '')
      .replaceFirst(_trailingBreak, '');
  return '<div class="html-preview-root">$flattened</div>';
}

/// 带 ruby 注音的简介不能按行高裁剪，否则注音被截断。
final RegExp _rubyTag = RegExp(r'<ruby[\s>]', caseSensitive: false);

bool htmlHasRuby(String html) => _rubyTag.hasMatch(html);

/// 简介 / 公告正文渲染器。预览模式压平排版，完整模式保留图片与块间距。
class BookHtmlContent extends StatelessWidget {
  const BookHtmlContent({
    super.key,
    required this.html,
    this.preview = false,
    this.textColor,
  });

  final String html;
  final bool preview;
  final Color? textColor;

  static const List<double> _fontTagSizes = <double>[
    0.63,
    0.82,
    1,
    1.13,
    1.5,
    2,
    3,
  ];

  Map<String, String>? _stylesFor(
    String? tag,
    Iterable<String> classes,
    double fontSize,
  ) {
    final styles = <String, String>{};
    switch (tag) {
      case 'h1':
        styles.addAll(_heading(fontSize * 1.65));
      case 'h2':
        styles.addAll(_heading(fontSize * 1.25));
      case 'h3':
        styles.addAll(_heading(fontSize * 0.95));
      case 'h4':
        styles.addAll(_subheading(fontSize * 1.5));
      case 'p':
        styles['margin'] = preview ? '0 0 8.4px 0' : '0 0 9.6px 0';
      case 'div':
        if (!preview) styles['margin'] = '0 0 6.4px 0';
      case 'ul':
      case 'ol':
        styles['padding-left'] = '1.5em';
      case 'li':
        styles['margin-bottom'] = '0.3em';
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
          styles['text-decoration'] = 'underline';
          styles['text-decoration-style'] = 'dotted';
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
          styles.addAll(_subheading(fontSize * 1.5));
        case 'illu':
        case 'illus':
        case 'duokan-image-single':
        case 'image-preview':
          styles['text-align'] = 'center';
        default:
          final scale = _emScale(className);
          if (scale != null) {
            styles['font-size'] = '${(fontSize * scale).toStringAsFixed(2)}px';
          }
      }
    }
    return styles.isEmpty ? null : styles;
  }

  static Map<String, String> _heading(double size) => <String, String>{
        'font-size': '${size.toStringAsFixed(2)}px',
        'font-weight': 'bold',
        'text-align': 'center',
        'line-height': '1.2',
      };

  static Map<String, String> _subheading(double size) => <String, String>{
        'font-size': '${size.toStringAsFixed(2)}px',
        'font-weight': 'bold',
        'padding-left': '1.333em',
      };

  /// 站内 `em05`…`em30` 类名表示相对字号，跳过 em10。
  static double? _emScale(String className) {
    if (className.length != 4 || !className.startsWith('em')) return null;
    final value = int.tryParse(className.substring(2));
    if (value == null || value < 5 || value > 30 || value == 10) return null;
    return value / 10;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fontSize = preview ? 14.0 : 16.0;
    final color =
        textColor ?? (preview ? colors.onSurfaceVariant : colors.onSurface);
    return HtmlWidget(
      preview ? createHtmlPreviewSource(html) : html,
      enableCaching: true,
      renderMode: RenderMode.column,
      textStyle: TextStyle(
        fontSize: fontSize,
        height: preview ? 1.6 : 1.8,
        color: color,
      ),
      customStylesBuilder: (element) {
        final styles = _stylesFor(element.localName, element.classes, fontSize);
        if (element.localName == 'a') {
          return <String, String>{
            ...?styles,
            'color': '#${colors.primary.toARGB32().toRadixString(16).substring(2)}',
            'text-decoration': 'underline',
          };
        }
        if (element.localName == 'font') {
          final size = int.tryParse(element.attributes['size'] ?? '');
          if (size != null && size >= 1 && size <= 7) {
            return <String, String>{
              ...?styles,
              'font-size':
                  '${(fontSize * _fontTagSizes[size - 1]).toStringAsFixed(2)}px',
            };
          }
        }
        return styles;
      },
      onTapImage: preview
          ? null
          : (metadata) => previewHtmlImage(context, metadata),
      onTapUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return false;
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      onErrorBuilder: (context, element, error) => Text(
        '内容无法显示。',
        style: TextStyle(fontSize: fontSize, color: colors.error),
      ),
      onLoadingBuilder: preview
          ? null
          : (context, element, loadingProgress) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
    );
  }
}
