import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/list_detail.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/settings_rows.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _resetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '重置所有设置',
      message: '内容、外观、阅读和缓存设置都会恢复默认值，账号与书架数据不受影响。',
      confirmLabel: '重置',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    ref.read(settingsControllerProvider).update((_) => const AppSettings());
    showAppSnackBar(context, '已恢复默认设置');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <Widget>[
      SettingsSection(
        title: '账号',
        children: <Widget>[
          SettingsNavigationRow(
            title: '个人资料',
            description: '账号信息、头像、成长记录与每日签到',
            icon: Icons.account_circle_outlined,
            onTap: () => context.openPage('/settings/profile'),
          ),
        ],
      ),
      SettingsSection(
        title: '通用',
        children: <Widget>[
          SettingsNavigationRow(
            title: '内容',
            description: '首页模块和内容筛选',
            icon: Icons.dashboard_outlined,
            onTap: () => context.openPage('/settings/content'),
          ),
          SettingsNavigationRow(
            title: '外观',
            description: '主题、颜色和显示样式',
            icon: Icons.palette_outlined,
            onTap: () => context.openPage('/settings/appearance'),
          ),
        ],
      ),
      SettingsSection(
        title: '阅读',
        children: <Widget>[
          SettingsNavigationRow(
            title: '小说',
            description: '小说排版、布局和阅读行为',
            icon: Icons.menu_book_outlined,
            onTap: () => context.openPage('/settings/reader/novel'),
          ),
          SettingsNavigationRow(
            title: '漫画',
            description: '漫画布局、分页方向和阅读行为',
            icon: Icons.photo_library_outlined,
            onTap: () => context.openPage('/settings/reader/comic'),
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
            onTap: () => context.openPage('/settings/cache'),
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
            onTap: () => context.openPage('/settings/about'),
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
            // 设置页可能由深链直接进入，无法回退时跳到发现页。
            leading: BackButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/discover'),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '重置所有设置',
                onPressed: () => _resetAll(context, ref),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
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
