import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../shared/widgets/settings_rows.dart';

/// 阅读设置页；正文与阅读器内的设置面板共用 [ReaderSettingsContent]。
class ReaderSettingsScreen extends StatelessWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('阅读')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 88),
      child: ReaderSettingsContent(),
    ),
  );
}

/// 阅读设置正文：不含滚动容器，可直接放进阅读器的底部面板。
class ReaderSettingsContent extends ConsumerWidget {
  const ReaderSettingsContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider);
    final scopes = settings.cleanChapterTitleScopes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSection(
            title: '排版',
            children: <Widget>[
              SettingsSliderRow(
                title: '字号',
                description: '小说阅读器使用的文字大小',
                icon: Icons.format_size,
                value: settings.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                format: (value) => '${value.round()} 点',
                onChanged: (value) => controller.update(
                  (settings) =>
                      settings.copyWith(fontSize: value.roundToDouble()),
                ),
              ),
              SettingsSliderRow(
                title: '行高',
                description: '段落中的行间距',
                icon: Icons.format_line_spacing,
                value: settings.readerLineHeight,
                min: 1,
                max: 2.5,
                divisions: 15,
                format: (value) => '${value.toStringAsFixed(1)} 倍',
                onChanged: (value) => controller.update(
                  // 滑块步进 0.1，取整到一位小数后落库，避免浮点误差堆积。
                  (settings) => settings.copyWith(
                    readerLineHeight: (value * 10).roundToDouble() / 10,
                  ),
                ),
              ),
              SettingsSliderRow(
                title: '行距',
                description: '段落之间的额外间距',
                icon: Icons.density_medium,
                value: settings.readerParagraphSpacing,
                min: 0,
                max: 16,
                divisions: 16,
                format: (value) => '${value.round()} 点',
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(
                    readerParagraphSpacing: value.roundToDouble(),
                  ),
                ),
              ),
              SettingsSliderRow(
                title: '两侧留白',
                description: '阅读内容两侧的水平留白',
                icon: Icons.space_bar,
                value: settings.readerSidePadding,
                min: 12,
                max: 64,
                divisions: 52,
                format: (value) => '${value.round()} 点',
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(
                    readerSidePadding: value.roundToDouble(),
                  ),
                ),
              ),
              SettingsToggleRow(
                title: '两端对齐',
                description: '调整字间距，使正文左右边缘对齐',
                icon: Icons.format_align_justify,
                value: settings.readerJustify,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(readerJustify: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSection(
            title: '章节标题',
            children: <Widget>[
              SettingsToggleRow(
                title: '继续阅读按钮',
                description: '继续阅读按钮仅显示章节编号或名称',
                icon: Icons.play_circle_outline,
                value: scopes.contains(CleanChapterTitleScope.continueReading),
                onChanged: (_) => controller.toggleCleanChapterTitleScope(
                  CleanChapterTitleScope.continueReading,
                ),
              ),
              SettingsToggleRow(
                title: '阅读器标题',
                description: '阅读器标题栏仅显示章节编号或名称',
                icon: Icons.title,
                value: scopes.contains(CleanChapterTitleScope.readerTitle),
                onChanged: (_) => controller.toggleCleanChapterTitleScope(
                  CleanChapterTitleScope.readerTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSection(
            title: '阅读行为',
            children: <Widget>[
              SettingsPickerRow<ComicPagedDirection>(
                title: '漫画分页方向',
                description: '设置漫画分页模式的点击与滑动方向',
                icon: Icons.swap_horiz,
                value: settings.comicPagedDirection,
                options: const <(ComicPagedDirection, String)>[
                  (ComicPagedDirection.ltr, '从左到右'),
                  (ComicPagedDirection.rtl, '从右到左'),
                ],
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(comicPagedDirection: value),
                ),
              ),
              SettingsPickerRow<ReaderViewMode>(
                title: '阅读模式',
                description: '选择滚动或逐页阅读',
                icon: Icons.view_day_outlined,
                value: settings.readerViewMode,
                options: const <(ReaderViewMode, String)>[
                  (ReaderViewMode.paged, '翻页'),
                  (ReaderViewMode.scroll, '滚动'),
                ],
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(readerViewMode: value),
                ),
              ),
              SettingsToggleRow(
                title: '使用音量键翻页',
                description: 'Android 沉浸阅读时：音量加键上一页，音量减键下一页',
                icon: Icons.volume_up_outlined,
                value: settings.readerVolumeKeyPagingEnabled,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(
                    readerVolumeKeyPagingEnabled: value,
                  ),
                ),
              ),
              SettingsToggleRow(
                title: '预渲染前后章节',
                description: '提前排好前后各一章，跨章翻页无缝衔接',
                icon: Icons.auto_stories_outlined,
                value: settings.readerPrerenderAdjacent,
                onChanged: (value) => controller.update(
                  (settings) =>
                      settings.copyWith(readerPrerenderAdjacent: value),
                ),
              ),
              SettingsToggleRow(
                title: '首行缩进',
                description: '每个段落的首行缩进',
                icon: Icons.format_indent_increase,
                value: settings.readerFirstLineIndent,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(readerFirstLineIndent: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
