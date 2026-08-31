import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/platform/reader_immersive_mode.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';
import '../../data/api/models/book.dart';
import '../../shared/widgets/color_picker_sheet.dart';
import '../../shared/widgets/settings_rows.dart';

/// 自定义阅读背景的预设色：浅色纸张与深色底各几档。
const List<String> _readerBackgroundPresets = <String>[
  '#FFFFFF',
  '#F7F1E3',
  '#EFE7D5',
  '#E3EDE3',
  '#E4EBF2',
  '#3B3A36',
  '#1B1815',
  '#000000',
];

/// 阅读设置页；正文与阅读器内的设置面板共用 [ReaderSettingsContent]。
class ReaderSettingsScreen extends StatelessWidget {
  const ReaderSettingsScreen({super.key, required this.type});

  final BookType type;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(type == BookType.comic ? '漫画阅读' : '小说阅读')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 88),
      child: ReaderSettingsContent(type: type),
    ),
  );
}

/// 阅读设置正文：不含滚动容器，可直接放进阅读器的底部面板。
class ReaderSettingsContent extends ConsumerWidget {
  const ReaderSettingsContent({super.key, required this.type});

  final BookType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider);
    final comic = type == BookType.comic;
    final reader = comic ? settings.comicReader : settings.novelReader;
    final customBackground =
        reader.backgroundMode == ReaderBackgroundMode.custom;
    final paged = reader.viewMode == ReaderViewMode.paged;
    final scopes = settings.cleanChapterTitleScopes;

    void updateReader(
      ReaderPreferences Function(ReaderPreferences current) update,
    ) {
      controller.update(
        (settings) => comic
            ? settings.copyWith(comicReader: update(settings.comicReader))
            : settings.copyWith(novelReader: update(settings.novelReader)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSection(
            title: '背景',
            children: <Widget>[
              SettingsPickerRow<ReaderBackgroundMode>(
                title: '阅读背景',
                description: '阅读器的底色与正文颜色',
                icon: Icons.wallpaper_outlined,
                value: reader.backgroundMode,
                options: const <(ReaderBackgroundMode, String)>[
                  (ReaderBackgroundMode.auto, '默认'),
                  (ReaderBackgroundMode.paper, '纸质'),
                  (ReaderBackgroundMode.custom, '自定义颜色'),
                ],
                onChanged: (value) => updateReader(
                  (reader) => reader.copyWith(backgroundMode: value),
                ),
              ),
              SettingsRow(
                title: '背景颜色',
                description: reader.backgroundColorValue,
                icon: Icons.colorize_outlined,
                enabled: customBackground,
                onTap: customBackground
                    ? () async {
                        final picked = await showColorPickerSheet(
                          context,
                          initial: reader.backgroundColorValue,
                          title: '背景颜色',
                          presets: _readerBackgroundPresets,
                        );
                        if (picked == null) return;
                        updateReader(
                          (reader) =>
                              reader.copyWith(backgroundColorValue: picked),
                        );
                      }
                    : null,
                trailing: _ColorSwatch(
                  color: parseSeedColor(reader.backgroundColorValue),
                ),
              ),
              if (customBackground)
                SettingsValueRow(
                  title: '阅读主题',
                  description: '自定义背景色的亮暗由底色决定',
                  icon: Icons.brightness_4_outlined,
                  value:
                      ThemeData.estimateBrightnessForColor(
                            parseSeedColor(reader.backgroundColorValue),
                          ) ==
                          Brightness.dark
                      ? '深色'
                      : '浅色',
                  enabled: false,
                )
              else
                SettingsPickerRow<ReaderThemeSetting>(
                  title: '阅读主题',
                  description: '阅读页单独的主题',
                  icon: Icons.brightness_4_outlined,
                  value: reader.theme,
                  options: const <(ReaderThemeSetting, String)>[
                    (ReaderThemeSetting.followApp, '跟随应用'),
                    (ReaderThemeSetting.light, '浅色'),
                    (ReaderThemeSetting.dark, '深色'),
                  ],
                  onChanged: (value) =>
                      updateReader((reader) => reader.copyWith(theme: value)),
                ),
            ],
          ),
          if (!comic) ...<Widget>[
            const SizedBox(height: 20),
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
                    (settings) => settings.copyWith(
                      readerLineHeight: (value * 10).roundToDouble() / 10,
                    ),
                  ),
                ),
                SettingsSliderRow(
                  title: '行距',
                  description: '段落之间的额外间距',
                  icon: Icons.density_medium,
                  value: settings.readerLineSpace,
                  min: 0,
                  max: 16,
                  divisions: 16,
                  format: (value) => '${value.round()} 点',
                  onChanged: (value) => controller.update(
                    (settings) => settings.copyWith(
                      readerLineSpace: value.roundToDouble(),
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
                SettingsToggleRow(
                  title: '首行缩进',
                  description: '每个段落的首行缩进',
                  icon: Icons.format_indent_increase,
                  value: settings.readerFirstLineIndent,
                  onChanged: (value) => controller.update(
                    (settings) =>
                        settings.copyWith(readerFirstLineIndent: value),
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
                  value: scopes.contains(
                    CleanChapterTitleScope.continueReading,
                  ),
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
          ],
          const SizedBox(height: 20),
          SettingsSection(
            title: '阅读行为',
            children: <Widget>[
              if (comic)
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
              SettingsToggleRow(
                title: '页码胶囊',
                description: '阅读时在角落常驻显示章节与页码',
                icon: Icons.pin_outlined,
                value: reader.statusPillsEnabled,
                enabled: reader.viewMode == ReaderViewMode.paged,
                onChanged: (value) => updateReader(
                  (reader) => reader.copyWith(statusPillsEnabled: value),
                ),
              ),
              SettingsPickerRow<ReaderViewMode>(
                title: '阅读模式',
                description: '选择滚动或逐页阅读',
                icon: Icons.view_day_outlined,
                value: reader.viewMode,
                options: const <(ReaderViewMode, String)>[
                  (ReaderViewMode.paged, '翻页'),
                  (ReaderViewMode.scroll, '滚动'),
                ],
                onChanged: (value) =>
                    updateReader((reader) => reader.copyWith(viewMode: value)),
              ),
              SettingsPickerRow<ReaderPageTurnAnimation>(
                title: '翻页动画',
                description: '点击或音量键翻页时的过渡效果',
                icon: Icons.animation_outlined,
                value: reader.pageTurnAnimation,
                options: const <(ReaderPageTurnAnimation, String)>[
                  (ReaderPageTurnAnimation.none, '无动画'),
                  (ReaderPageTurnAnimation.slide, '平滑滑动'),
                ],
                enabled: paged,
                onChanged: (value) => updateReader(
                  (reader) => reader.copyWith(pageTurnAnimation: value),
                ),
              ),
              SettingsToggleRow(
                title: '双页模式',
                description: '横屏且屏幕够宽时并排显示两栏，仅翻页模式生效',
                icon: Icons.auto_stories,
                value: reader.dualPageEnabled,
                enabled: paged,
                onChanged: (value) => updateReader(
                  (reader) => reader.copyWith(dualPageEnabled: value),
                ),
              ),
              if (comic)
                SettingsToggleRow(
                  title: '错位双页',
                  description: '第一页作为封面单独显示，后续页面双页并排',
                  icon: Icons.menu_book_outlined,
                  value: reader.dualPageOffsetEnabled,
                  enabled: paged && reader.dualPageEnabled,
                  onChanged: (value) => updateReader(
                    (reader) => reader.copyWith(dualPageOffsetEnabled: value),
                  ),
                ),
              if (readerImmersiveSupported)
                SettingsToggleRow(
                  title: '沉浸式阅读',
                  description: '阅读时隐藏状态栏和导航栏',
                  icon: Icons.fullscreen,
                  value: reader.immersiveEnabled,
                  onChanged: (value) => updateReader(
                    (reader) => reader.copyWith(immersiveEnabled: value),
                  ),
                ),
              if (defaultTargetPlatform == TargetPlatform.android)
                SettingsToggleRow(
                  title: '使用音量键翻页',
                  description: '沉浸阅读时：音量加键上一页，音量减键下一页',
                  icon: Icons.volume_up_outlined,
                  value: reader.volumeKeyPagingEnabled,
                  onChanged: (value) => updateReader(
                    (reader) => reader.copyWith(volumeKeyPagingEnabled: value),
                  ),
                ),
              if (!comic)
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
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置行尾的颜色圆点。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
