import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/settings_rows.dart';

Future<void> showSettingsAlert({
  required BuildContext context,
  required String title,
  String? message,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: message == null ? null : Text(message),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('好'),
      ),
    ],
  ),
);

/// 二次确认弹窗；`destructive` 用于退出登录一类的破坏性操作。
Future<bool> showSettingsConfirm({
  required BuildContext context,
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: colors.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      SettingsSection(
        title: '账号',
        children: <Widget>[
          SettingsNavigationRow(
            title: '个人资料',
            description: '账号信息、头像、成长记录与每日签到',
            icon: Icons.account_circle_outlined,
            onTap: () => context.push('/settings/profile'),
          ),
        ],
      ),
      SettingsSection(
        title: '通用',
        children: <Widget>[
          SettingsNavigationRow(
            title: '阅读',
            description: '排版、布局和阅读行为',
            icon: Icons.menu_book_outlined,
            onTap: () => context.push('/settings/reader'),
          ),
          SettingsNavigationRow(
            title: '内容',
            description: '首页模块和内容筛选',
            icon: Icons.dashboard_outlined,
            onTap: () => context.push('/settings/content'),
          ),
          SettingsNavigationRow(
            title: '外观',
            description: '主题、颜色和显示样式',
            icon: Icons.palette_outlined,
            onTap: () => context.push('/settings/appearance'),
          ),
        ],
      ),
      SettingsSection(
        title: '数据',
        children: <Widget>[
          SettingsNavigationRow(
            title: '缓存',
            description: '缓存策略和本地存储',
            icon: Icons.storage_outlined,
            onTap: () => context.push('/settings/cache'),
          ),
        ],
      ),
      SettingsSection(
        title: '关于',
        children: <Widget>[
          SettingsNavigationRow(
            title: '应用相关',
            description: '版本与官网',
            icon: Icons.info_outline,
            onTap: () => context.push('/settings/about'),
          ),
        ],
      ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            title: const Text('设置'),
            // 设置页可能由深链直接进入，此时回退到发现页而不是留在空栈。
            leading: BackButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/discover'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
            sliver: SliverList.separated(
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 20),
              itemBuilder: (_, index) => sections[index],
            ),
          ),
        ],
      ),
    );
  }
}
