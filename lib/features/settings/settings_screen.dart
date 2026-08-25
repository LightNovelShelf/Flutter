import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/settings_rows.dart';

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
        title: '阅读',
        children: <Widget>[
          SettingsNavigationRow(
            title: '小说',
            description: '小说排版、布局和阅读行为',
            icon: Icons.menu_book_outlined,
            onTap: () => context.push('/settings/reader/novel'),
          ),
          SettingsNavigationRow(
            title: '漫画',
            description: '漫画布局、分页方向和阅读行为',
            icon: Icons.photo_library_outlined,
            onTap: () => context.push('/settings/reader/comic'),
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
            // 设置页可能由深链直接进入，无法回退时跳到发现页。
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
