import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/html/reader_content_style.dart';
import '../../../shared/widgets/image_preview.dart';
import '../../../shared/widgets/reader_html_block.dart';
import '../../reader/reader_html_blocks.dart';

/// 帖子正文。`splitContentHtmlBlocks` 要整篇跑正则清理再挑叶子节点，
/// 结果缓存在 State 上按 html 复用，解析本身推到当帧之后，别拖长这一帧。
class CommunityThreadBody extends StatefulWidget {
  const CommunityThreadBody({
    super.key,
    required this.html,
    required this.color,
  });

  final String html;
  final Color color;

  @override
  State<CommunityThreadBody> createState() => _CommunityThreadBodyState();
}

class _CommunityThreadBodyState extends State<CommunityThreadBody> {
  List<String>? _blocks;

  @override
  void initState() {
    super.initState();
    _parseAfterFrame();
  }

  @override
  void didUpdateWidget(CommunityThreadBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _blocks = null;
      _parseAfterFrame();
    }
  }

  void _parseAfterFrame() {
    final html = widget.html;
    Future<void>.microtask(() {
      if (!mounted || widget.html != html) return;
      final blocks = splitContentHtmlBlocks(html);
      if (!mounted) return;
      setState(() => _blocks = blocks);
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    if (blocks == null) return const SizedBox.shrink();
    final style = ReaderContentStyle(
      fontSize: 16,
      lineHeight: 1.5,
      paragraphSpacing: 8,
      firstLineIndent: false,
      justify: false,
    );
    return DefaultTextStyle.merge(
      style: TextStyle(color: widget.color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < blocks.length; index++)
            ReaderHtmlBlock(
              markup: blocks[index],
              style: style,
              onTapUrl: _openExternalUrl,
              borderIllustrations: false,
              imagePreviewTrigger: ImagePreviewTrigger.tap,
              applyParagraphSpacing: index + 1 < blocks.length,
            ),
        ],
      ),
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
