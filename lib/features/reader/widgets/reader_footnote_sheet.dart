import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/html/reader_content_style.dart';
import '../../../shared/widgets/image_preview.dart';

/// 脚注弹层。注文与正文共用章节混淆字体，需要传入字体族名。
Future<void> showReaderFootnoteSheet(
  BuildContext context, {
  required String html,
  String? fontFamily,
}) => showDraggableSheet<void>(
  context,
  initialSize: 0.55,
  showDragHandle: true,
  builder: (context, controller) => _ReaderFootnoteSheet(
    html: html,
    fontFamily: fontFamily,
    scrollController: controller,
  ),
);

class _ReaderFootnoteSheet extends StatelessWidget {
  const _ReaderFootnoteSheet({
    required this.html,
    required this.scrollController,
    this.fontFamily,
  });

  final String html;
  final String? fontFamily;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = ReaderContentStyle(
      fontSize: 16,
      lineHeight: 1.7,
      color: colors.onSurface,
      firstLineIndent: false,
      justify: false,
      fontFamily: fontFamily,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(icon: Icons.sticky_note_2_outlined, title: '注释'),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: HtmlWidget(
              html,
              renderMode: RenderMode.column,
              textStyle: style.textStyle,
              customStylesBuilder: (element) {
                final styles = style.stylesFor(
                  tag: element.localName,
                  classes: element.classes,
                  attributes: const <String, String>{},
                );
                // 注文按段落阅读，补段间距；列表补左内边距容纳项目符号。
                return switch (element.localName) {
                  'p' => <String, String>{...?styles, 'margin': '0 0 0.8em'},
                  'ol' ||
                  'ul' => <String, String>{...?styles, 'padding-left': '1.2em'},
                  _ => styles,
                };
              },
              onTapImage: (metadata) => previewHtmlImage(context, metadata),
              onErrorBuilder: (context, element, error) => Text(
                '注释无法显示。',
                style: TextStyle(fontSize: 16, color: colors.error),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
