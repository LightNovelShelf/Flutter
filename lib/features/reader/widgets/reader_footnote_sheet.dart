import 'package:flutter/material.dart';

import '../../../data/settings/app_settings.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/html_content.dart';

/// 脚注弹层。注文与正文共用章节混淆字体，需要传入字体族名。
///
/// [imageMode] 与正文的图像显示方式一致：“不显示”略去注文里的图片；“点击显示”先略去，
/// 注文下方摆一个按钮，点了再把这条注文的图片全部显示出来。
Future<void> showReaderFootnoteSheet(
  BuildContext context, {
  required String html,
  String? fontFamily,
  ReaderImageMode imageMode = ReaderImageMode.show,
}) => showDraggableSheet<void>(
  context,
  initialSize: 0.55,
  showDragHandle: true,
  builder: (context, controller) => _ReaderFootnoteSheet(
    html: html,
    fontFamily: fontFamily,
    imageMode: imageMode,
    scrollController: controller,
  ),
);

class _ReaderFootnoteSheet extends StatefulWidget {
  const _ReaderFootnoteSheet({
    required this.html,
    required this.imageMode,
    required this.scrollController,
    this.fontFamily,
  });

  final String html;
  final String? fontFamily;
  final ReaderImageMode imageMode;
  final ScrollController scrollController;

  @override
  State<_ReaderFootnoteSheet> createState() => _ReaderFootnoteSheetState();
}

class _ReaderFootnoteSheetState extends State<_ReaderFootnoteSheet> {
  /// “点击显示”模式下点过按钮；只管这一次弹层，关掉再开要重新点。
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final withoutImages = widget.imageMode == ReaderImageMode.show
        ? widget.html
        : removeHtmlImages(widget.html);
    // 注文里没有图片时不摆按钮。
    final masked =
        widget.imageMode == ReaderImageMode.tapToShow &&
        !_revealed &&
        withoutImages.length != widget.html.length;
    final showImages =
        widget.imageMode == ReaderImageMode.tapToShow && _revealed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(icon: Icons.sticky_note_2_outlined, title: '注释'),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                HtmlContentTheme.merge(
                  data: HtmlContentThemeData(
                    textStyle: TextStyle(
                      color: colors.onSurface,
                      fontFamily: widget.fontFamily,
                    ),
                  ),
                  child: HtmlContent(
                    html: showImages ? widget.html : withoutImages,
                  ),
                ),
                if (masked)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _revealed = true),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text('显示图像'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
