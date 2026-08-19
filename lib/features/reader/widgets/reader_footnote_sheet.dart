import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 脚注弹层。注文本身也用了章节混淆字体，必须在 WebView 里带着 `@font-face` 渲染。
Future<void> showReaderFootnoteSheet(
  BuildContext context, {
  required String html,
  String? fontDataUrl,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: _ReaderFootnoteSheet(html: html, fontDataUrl: fontDataUrl),
      ),
    );

class _ReaderFootnoteSheet extends StatefulWidget {
  const _ReaderFootnoteSheet({required this.html, this.fontDataUrl});

  final String html;
  final String? fontDataUrl;

  @override
  State<_ReaderFootnoteSheet> createState() => _ReaderFootnoteSheetState();
}

class _ReaderFootnoteSheetState extends State<_ReaderFootnoteSheet> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled);
  bool _loaded = false;
  String? _document;

  String _buildDocument(ColorScheme colors) {
    final fontFace = widget.fontDataUrl == null
        ? ''
        : "@font-face{font-family:'ChapterFont';font-display:block;"
            'src:url(${widget.fontDataUrl});}';
    final family = widget.fontDataUrl == null
        ? "'PingFang SC','Noto Sans SC',sans-serif"
        : "'ChapterFont','PingFang SC','Noto Sans SC',sans-serif";
    return '<!DOCTYPE html><html><head><meta charset="utf-8" />'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0, '
        'maximum-scale=1.0, user-scalable=no" /><style>$fontFace'
        'html,body{margin:0;padding:0;background:${_hex(colors.surface)};'
        'color:${_hex(colors.onSurface)}}'
        'body{font-family:$family;font-size:16px;line-height:1.7;'
        'word-break:break-word;overflow-wrap:break-word}'
        'p{margin:0 0 .8em}'
        'ol,ul{margin:0 0 .8em;padding:0;list-style-position:inside}'
        'img{max-width:100%;height:auto}'
        '*{-webkit-user-select:none!important;user-select:none!important}'
        '</style></head><body>${widget.html}</body></html>';
  }

  static String _hex(Color color) =>
      '#${((color.toARGB32()) & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final document = _buildDocument(Theme.of(context).colorScheme);
    if (document == _document) return;
    _document = document;
    _controller
      ..setBackgroundColor(Theme.of(context).colorScheme.surface)
      ..loadHtmlString(document).then((_) {
        if (mounted) setState(() => _loaded = true);
      });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.sticky_note_2_outlined, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                '注释',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Stack(
              children: <Widget>[
                Opacity(
                  opacity: _loaded ? 1 : 0,
                  child: WebViewWidget(controller: _controller),
                ),
                if (!_loaded)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
