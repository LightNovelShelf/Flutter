import 'package:flutter/material.dart';

import '../../../shared/widgets/app_sheet.dart';
import '../../settings/reader_settings_screen.dart';

/// 设置弹层：与设置页共用 `ReaderSettingsContent`，改动即时生效，阅读位置不丢。
Future<void> showReaderSettingsSheet(BuildContext context) =>
    showDraggableSheet<void>(
      context,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.zero,
        children: const <Widget>[
          SheetHeader(
            icon: Icons.tune,
            title: '阅读设置',
            padding: EdgeInsets.fromLTRB(24, 12, 24, 4),
          ),
          ReaderSettingsContent(),
        ],
      ),
    );
