import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/widgets/app_sheet.dart';
import 'book_html_content.dart';

/// 在可拖到全屏的抽屉里展示完整简介。
void showBookIntroductionSheet(BuildContext context, BookDetail detail) {
  showDraggableSheet<void>(
    context,
    initialSize: 0.7,
    minSize: 0.4,
    showDragHandle: true,
    builder: (sheetContext, controller) {
      final colors = Theme.of(sheetContext).colorScheme;
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        children: <Widget>[
          const SheetHeader(
            icon: Icons.subject,
            title: '简介',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          BookHtmlContent(
            html: detail.introduction,
            textColor: colors.onSurfaceVariant,
          ),
        ],
      );
    },
  );
}
