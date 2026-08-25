import 'package:flutter/material.dart';

import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/html_content.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(icon: Icons.sticky_note_2_outlined, title: '注释'),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: HtmlContentTheme.merge(
              data: HtmlContentThemeData(
                textStyle: TextStyle(
                  color: colors.onSurface,
                  fontFamily: fontFamily,
                ),
              ),
              child: HtmlContent(html: html),
            ),
          ),
        ),
      ],
    );
  }
}
