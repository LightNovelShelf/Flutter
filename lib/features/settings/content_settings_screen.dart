import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/widgets/settings_rows.dart';
import 'badge_legend_sheet.dart';

class ContentSettingsScreen extends ConsumerWidget {
  const ContentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('内容')),
      body: SettingsList(
        children: <Widget>[
          SettingsSection(
            title: '首页',
            children: <Widget>[
              SettingsPickerRow<HomeRankType>(
                title: '首页排行榜',
                description: '选择首页显示的排行榜',
                icon: Icons.leaderboard_outlined,
                value: settings.homeRankType,
                options: const <(HomeRankType, String)>[
                  (HomeRankType.daily, '日榜'),
                  (HomeRankType.weekly, '周榜'),
                  (HomeRankType.monthly, '月榜'),
                ],
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(homeRankType: value),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '内容筛选',
            children: <Widget>[
              SettingsToggleRow(
                title: '隐藏日文内容',
                description: '在发现列表中隐藏日文作品',
                icon: Icons.translate,
                value: settings.ignoreJapanese,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(ignoreJapanese: value),
                ),
              ),
              SettingsToggleRow(
                title: '隐藏 AI 内容',
                description: '在发现列表中隐藏带有 AI 标签的书籍',
                icon: Icons.smart_toy_outlined,
                value: settings.ignoreAI,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(ignoreAI: value),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '搜索',
            children: <Widget>[
              SettingsPickerRow<SeriesSearchMode>(
                title: '系列名称搜索',
                description: '选择详情页快捷搜索使用的系列名称',
                icon: Icons.search,
                value: settings.seriesSearchMode,
                options: const <(SeriesSearchMode, String)>[
                  (SeriesSearchMode.system, '自动选择'),
                  (SeriesSearchMode.original, '原名'),
                  (SeriesSearchMode.display, '显示名称'),
                ],
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(seriesSearchMode: value),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '书籍徽章',
            children: <Widget>[
              SettingsNavigationRow(
                title: '徽章含义',
                description: '预览全部书籍封面徽章及其含义',
                icon: Icons.workspace_premium_outlined,
                onTap: () => showBadgeLegendSheet(context),
              ),
            ],
          ),
          SettingsSection(
            title: '文字转换',
            children: <Widget>[
              SettingsPickerRow<ConvertType>(
                title: '简繁转换',
                description: '阅读时转换正文文字',
                icon: Icons.swap_horiz,
                value: settings.convertType,
                options: const <(ConvertType, String)>[
                  (ConvertType.none, '关闭'),
                  (ConvertType.t2s, '繁体转简体'),
                  (ConvertType.s2t, '简体转繁体'),
                ],
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(convertType: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
