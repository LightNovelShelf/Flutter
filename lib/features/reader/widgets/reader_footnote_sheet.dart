import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../shared/widgets/image_preview.dart';
import '../reader_content_style.dart';

/// 脚注弹层。注文与正文共用章节混淆字体，字体族名必须一路传到这里。
Future<void> showReaderFootnoteSheet(
  BuildContext context, {
  required String html,
  String? fontFamily,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  showDragHandle: false,
  isScrollControlled: true,
  useRootNavigator: true,
  builder: (context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 24,
              child: Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _ReaderFootnoteSheet(html: html, fontFamily: fontFamily),
            ),
          ],
        ),
      ),
    );
  },
);

class _ReaderFootnoteSheet extends StatelessWidget {
  const _ReaderFootnoteSheet({required this.html, this.fontFamily});

  final String html;
  final String? fontFamily;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.sticky_note_2_outlined,
                size: 22,
                color: colors.primary,
              ),
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
            child: SingleChildScrollView(
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
                  // 注文是独立成段读的，段间要有喘息，列表也得让出项目符号的位置。
                  return switch (element.localName) {
                    'p' => <String, String>{...?styles, 'margin': '0 0 0.8em'},
                    'ol' || 'ul' => <String, String>{
                      ...?styles,
                      'padding-left': '1.2em',
                    },
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
      ),
    );
  }
}
