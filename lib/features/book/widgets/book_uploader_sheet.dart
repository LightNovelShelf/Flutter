import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/user_avatar.dart';

/// 上传者名片，用自适应高度的底部弹窗。`showDraggableSheet` 会占满大半屏。
void showBookUploaderSheet(BuildContext context, BookDetailUser? user) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      final text = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SheetHeader(
              icon: Icons.account_circle_outlined,
              title: '上传者信息',
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      UserAvatar(
                        url: user?.avatarUrl ?? '',
                        name: user?.userName ?? '',
                        size: 56,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              user?.userName.isNotEmpty == true
                                  ? user!.userName
                                  : '未知上传者',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user == null ? '没有上传者资料' : '书籍上传者',
                              style: text.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (user != null && user.id > 0) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.badge_outlined,
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'UID',
                                style: text.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              SelectableText(
                                '${user.id}',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
