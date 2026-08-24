import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../data/settings/app_settings.dart';

/// 纸质背景的配色：底色取纸纹贴图的平均色，工具栏与贴图接缝处才不会露出色差。
class ReaderPaperPalette {
  const ReaderPaperPalette._();

  static const Color lightBackground = Color(0xFFE0C4A1);
  static const Color lightForeground = Color(0xFF2A2318);
  static const Color darkBackground = Color(0xFF384042);
  static const Color darkForeground = Color(0xFFE2E5E6);
}

/// 阅读器整屏的底色与前景色。
///
/// 默认跟随应用主题，OLED 纯黑时用纯黑与纯白，深色主题的浅灰底在 OLED 上会发亮；
/// 纸质按明暗取两套固定配色；自定义颜色的前景色按背景的感知亮度在黑白之间挑。
({Color background, Color foreground}) readerSurfaceColors(
  BuildContext context, {
  required ReaderBackgroundMode mode,
  required String customColorValue,
  required bool oledBlack,
}) {
  switch (mode) {
    case ReaderBackgroundMode.auto:
      final theme = Theme.of(context);
      final oled = theme.brightness == Brightness.dark && oledBlack;
      final colors = theme.colorScheme;
      return (
        background: oled ? Colors.black : colors.surface,
        foreground: oled ? Colors.white : colors.onSurface,
      );
    case ReaderBackgroundMode.paper:
      return Theme.of(context).brightness == Brightness.dark
          ? (
              background: ReaderPaperPalette.darkBackground,
              foreground: ReaderPaperPalette.darkForeground,
            )
          : (
              background: ReaderPaperPalette.lightBackground,
              foreground: ReaderPaperPalette.lightForeground,
            );
    case ReaderBackgroundMode.custom:
      final background = parseSeedColor(customColorValue);
      return (background: background, foreground: onAccentColor(background));
  }
}

/// 阅读器悬浮工具栏，默认隐藏，点中间区域显示。
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.currentChapter,
    required this.totalChapters,
    this.chapterTitles = const <String>[],
    required this.onOpenChapters,
    required this.nightMode,
    required this.onToggleNightMode,
    required this.onOpenSettings,
    required this.onDismiss,
    this.progress,
    this.onPreviousChapter,
    this.onNextChapter,
    this.onChapterSelected,
  });

  final bool visible;
  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final int currentChapter;
  final int totalChapters;
  final List<String> chapterTitles;
  final double? progress;
  final VoidCallback onOpenChapters;
  final bool nightMode;

  /// 为空表示当前不许切主题（自定义背景色下亮暗由底色定），按钮置灰。
  final VoidCallback? onToggleNightMode;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ValueChanged<int>? onChapterSelected;

  static const Duration _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: _duration,
              curve: Curves.easeOutCubic,
              offset: visible ? Offset.zero : const Offset(0, -1),
              child: _ReaderTopBar(
                title: title,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                topInset: padding.top,
                currentChapter: currentChapter,
                totalChapters: totalChapters,
                progress: progress,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              duration: _duration,
              curve: Curves.easeOutCubic,
              offset: visible ? Offset.zero : const Offset(0, 1),
              child: _ReaderBottomBar(
                visible: visible,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                bottomInset: padding.bottom,
                currentChapter: currentChapter,
                totalChapters: totalChapters,
                chapterTitles: chapterTitles,
                progress: progress,
                nightMode: nightMode,
                onOpenChapters: onOpenChapters,
                onToggleNightMode: onToggleNightMode,
                onOpenSettings: onOpenSettings,
                onPreviousChapter: onPreviousChapter,
                onNextChapter: onNextChapter,
                onChapterSelected: onChapterSelected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.topInset,
    required this.currentChapter,
    required this.totalChapters,
    required this.progress,
  });

  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final double topInset;
  final int currentChapter;
  final int totalChapters;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final secondary = foregroundColor.withValues(alpha: 0.68);
    final progressValue = progress?.clamp(0.0, 1.0);
    final subtitle = [
      if (totalChapters > 0) '第 $currentChapter / $totalChapters 章',
      if (progressValue != null) '已读 ${(progressValue * 100).round()}%',
    ].join('  ·  ');
    return Material(
      color: backgroundColor,
      elevation: 3,
      shadowColor: foregroundColor.withValues(alpha: 0.18),
      child: Padding(
        padding: EdgeInsets.only(top: topInset, right: 16),
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: '返回',
                onPressed: () => context.pop(),
                color: foregroundColor,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 16,
                        height: 20 / 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          height: 16 / 12,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatefulWidget {
  const _ReaderBottomBar({
    required this.visible,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.bottomInset,
    required this.currentChapter,
    required this.totalChapters,
    required this.chapterTitles,
    required this.progress,
    required this.nightMode,
    required this.onOpenChapters,
    required this.onToggleNightMode,
    required this.onOpenSettings,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onChapterSelected,
  });

  final bool visible;
  final Color backgroundColor;
  final Color foregroundColor;
  final double bottomInset;
  final int currentChapter;
  final int totalChapters;
  final List<String> chapterTitles;
  final double? progress;
  final bool nightMode;
  final VoidCallback onOpenChapters;
  final VoidCallback? onToggleNightMode;
  final VoidCallback onOpenSettings;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ValueChanged<int>? onChapterSelected;

  @override
  State<_ReaderBottomBar> createState() => _ReaderBottomBarState();
}

class _ReaderBottomBarState extends State<_ReaderBottomBar> {
  static const double _chapterNavigationHeight = 60;
  static const double _menuHeight = 64;
  static const double _previewGap = 16;

  /// 拖动中的目标章节，滑杆位置与气泡共用一份。松手、工具栏收起、外部章节变化都要
  /// 清空，否则选章失败后滑杆会停在没能打开的那一章。
  final ValueNotifier<int?> _preview = ValueNotifier<int?>(null);

  @override
  void didUpdateWidget(covariant _ReaderBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible ||
        oldWidget.currentChapter != widget.currentChapter ||
        oldWidget.totalChapters != widget.totalChapters) {
      _preview.value = null;
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final disabled = widget.foregroundColor.withValues(alpha: 0.38);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Material(
      color: widget.backgroundColor,
      elevation: 8,
      shadowColor: widget.foregroundColor.withValues(alpha: 0.18),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (progress != null)
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: widget.foregroundColor.withValues(
                    alpha: 0.12,
                  ),
                ),
              SizedBox(
                height: _chapterNavigationHeight,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: TextButton.icon(
                        onPressed: widget.onPreviousChapter,
                        style: TextButton.styleFrom(
                          foregroundColor: widget.foregroundColor,
                          disabledForegroundColor: disabled,
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('上一章'),
                      ),
                    ),
                    if (widget.totalChapters > 1)
                      Expanded(
                        flex: 5,
                        child: _ReaderChapterSlider(
                          preview: _preview,
                          currentChapter: widget.currentChapter,
                          totalChapters: widget.totalChapters,
                          backgroundColor: widget.backgroundColor,
                          foregroundColor: widget.foregroundColor,
                          onChapterSelected: widget.onChapterSelected,
                        ),
                      ),
                    Expanded(
                      flex: 3,
                      child: TextButton.icon(
                        onPressed: widget.onNextChapter,
                        style: TextButton.styleFrom(
                          foregroundColor: widget.foregroundColor,
                          disabledForegroundColor: disabled,
                          padding: EdgeInsets.zero,
                        ),
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('下一章'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: _menuHeight,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _ReaderMenuButton(
                        icon: Icons.list_alt_rounded,
                        label: '目录',
                        foregroundColor: widget.foregroundColor,
                        onPressed: widget.onOpenChapters,
                      ),
                    ),
                    Expanded(
                      child: _ReaderMenuButton(
                        icon: widget.nightMode
                            ? Icons.dark_mode_rounded
                            : Icons.dark_mode_outlined,
                        label: '夜间',
                        foregroundColor: widget.foregroundColor,
                        semanticLabel: '夜间模式',
                        toggled: widget.nightMode,
                        onPressed: widget.onToggleNightMode,
                      ),
                    ),
                    Expanded(
                      child: _ReaderMenuButton(
                        icon: Icons.tune_rounded,
                        label: '设置',
                        foregroundColor: widget.foregroundColor,
                        onPressed: widget.onOpenSettings,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: widget.bottomInset),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom:
                widget.bottomInset +
                _chapterNavigationHeight +
                _menuHeight +
                _previewGap,
            child: IgnorePointer(
              child: ValueListenableBuilder<int?>(
                valueListenable: _preview,
                builder: (context, previewChapter, _) => AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  reverseDuration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 90),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  ),
                  child: previewChapter == null
                      ? const SizedBox.shrink(key: ValueKey<bool>(false))
                      : _ReaderChapterPreview(
                          key: const ValueKey<bool>(true),
                          chapter: previewChapter,
                          totalChapters: widget.totalChapters,
                          chapterTitles: widget.chapterTitles,
                          backgroundColor: widget.backgroundColor,
                          foregroundColor: widget.foregroundColor,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderChapterPreview extends StatelessWidget {
  const _ReaderChapterPreview({
    super.key,
    required this.chapter,
    required this.totalChapters,
    required this.chapterTitles,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final int chapter;
  final int totalChapters;
  final List<String> chapterTitles;
  final Color backgroundColor;
  final Color foregroundColor;

  String get _title {
    if (chapter < 1 || chapter > chapterTitles.length) return '第$chapter章';
    final title = chapterTitles[chapter - 1].trim();
    return title.isEmpty ? '第$chapter章' : title;
  }

  @override
  Widget build(BuildContext context) {
    final surface = Color.alphaBlend(
      foregroundColor.withValues(alpha: 0.74),
      backgroundColor,
    );
    final onSurface = onAccentColor(surface);
    final percentage = totalChapters <= 0 ? 0.0 : chapter / totalChapters * 100;

    return Material(
      color: surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                height: 22 / 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.76),
                fontSize: 14,
                height: 18 / 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderMenuButton extends StatelessWidget {
  const _ReaderMenuButton({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.onPressed,
    this.semanticLabel,
    this.toggled,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool? toggled;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: foregroundColor,
      disabledForegroundColor: foregroundColor.withValues(alpha: 0.38),
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
    ),
    // 语义只能放在按钮里面：包住 TextButton 会把点击动作一起排除，读屏就点不动了。
    child: Semantics(
      label: semanticLabel,
      toggled: toggled,
      excludeSemantics: semanticLabel != null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 13, height: 16 / 13)),
        ],
      ),
    ),
  );
}

class _ReaderChapterSlider extends StatelessWidget {
  const _ReaderChapterSlider({
    required this.preview,
    required this.currentChapter,
    required this.totalChapters,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onChapterSelected,
  });

  final ValueNotifier<int?> preview;
  final int currentChapter;
  final int totalChapters;
  final Color backgroundColor;
  final Color foregroundColor;
  final ValueChanged<int>? onChapterSelected;

  int _chapterAt(double value) => value.round().clamp(1, totalChapters).toInt();

  @override
  Widget build(BuildContext context) {
    final onSelected = onChapterSelected;
    final activeTrack = foregroundColor.withValues(alpha: 0.38);
    final inactiveTrack = foregroundColor.withValues(alpha: 0.14);
    final thumb = Color.alphaBlend(
      foregroundColor.withValues(alpha: 0.12),
      backgroundColor,
    );

    return Center(
      child: SizedBox(
        height: 38,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            activeTrackColor: activeTrack,
            inactiveTrackColor: inactiveTrack,
            disabledActiveTrackColor: activeTrack,
            disabledInactiveTrackColor: inactiveTrack,
            thumbColor: thumb,
            disabledThumbColor: thumb,
            overlayColor: foregroundColor.withValues(alpha: 0.10),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 13,
              disabledThumbRadius: 13,
              elevation: 1,
              pressedElevation: 2,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: ValueListenableBuilder<int?>(
            valueListenable: preview,
            builder: (context, previewChapter, _) => Slider(
              value: (previewChapter ?? currentChapter)
                  .clamp(1, totalChapters)
                  .toDouble(),
              min: 1,
              max: totalChapters.toDouble(),
              semanticFormatterCallback: (value) =>
                  '第 ${value.round()} 章，共 $totalChapters 章',
              onChangeStart: onSelected == null
                  ? null
                  : (value) => preview.value = _chapterAt(value),
              onChanged: onSelected == null
                  ? null
                  : (value) => preview.value = _chapterAt(value),
              onChangeEnd: onSelected == null
                  ? null
                  : (value) {
                      final chapter = _chapterAt(value);
                      preview.value = null;
                      if (chapter != currentChapter) onSelected(chapter);
                    },
            ),
          ),
        ),
      ),
    );
  }
}
