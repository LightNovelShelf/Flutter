import 'package:flutter/material.dart';

import '../../settings/reader_settings_screen.dart';

/// 设置弹层：与设置页共用 `ReaderSettingsContent`，改动即时生效，阅读位置不丢。
Future<void> showReaderSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 1,
        snap: true,
        snapSizes: const <double>[0.6, 1],
        builder: (context, controller) {
          final colors = Theme.of(context).colorScheme;
          return ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.tune, size: 22, color: colors.primary),
                    const SizedBox(width: 10),
                    Text(
                      '阅读设置',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const ReaderSettingsContent(),
            ],
          );
        },
      ),
    );
