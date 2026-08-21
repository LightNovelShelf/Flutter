import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/settings/app_settings.dart';

/// 阅读器整屏的底/前景色。OLED 纯黑模式要真黑真白，深色主题的浅灰底在 OLED 上会发亮。
({Color background, Color foreground}) readerSurfaceColors(
  BuildContext context,
  AppSettings settings,
) {
  final theme = Theme.of(context);
  final oled = theme.brightness == Brightness.dark && settings.oledBlack;
  final colors = theme.colorScheme;
  return (
    background: oled ? Colors.black : colors.surface,
    foreground: oled ? Colors.white : colors.onSurface,
  );
}

/// 阅读器悬浮工具栏：默认隐藏，点中间区域才出现，不挡正文。
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.currentChapter,
    required this.totalChapters,
    required this.onOpenChapters,
    required this.onOpenSettings,
    required this.onDismiss,
    this.progress,
    this.onPreviousChapter,
    this.onNextChapter,
  });

  final bool visible;
  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final int currentChapter;
  final int totalChapters;
  final double? progress;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

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
                onOpenChapters: onOpenChapters,
                onOpenSettings: onOpenSettings,
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
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                bottomInset: padding.bottom,
                currentChapter: currentChapter,
                totalChapters: totalChapters,
                progress: progress,
                onPreviousChapter: onPreviousChapter,
                onNextChapter: onNextChapter,
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
    required this.onOpenChapters,
    required this.onOpenSettings,
  });

  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final double topInset;
  final int currentChapter;
  final int totalChapters;
  final double? progress;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;

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
        padding: EdgeInsets.only(top: topInset),
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
              PopupMenuButton<_ReaderMenuAction>(
                tooltip: '更多',
                color: backgroundColor,
                iconColor: foregroundColor,
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case _ReaderMenuAction.chapters:
                      onOpenChapters();
                    case _ReaderMenuAction.settings:
                      onOpenSettings();
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<_ReaderMenuAction>>[
                  PopupMenuItem<_ReaderMenuAction>(
                    value: _ReaderMenuAction.chapters,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.list, color: foregroundColor),
                        const SizedBox(width: 12),
                        Text('章节列表', style: TextStyle(color: foregroundColor)),
                      ],
                    ),
                  ),
                  PopupMenuItem<_ReaderMenuAction>(
                    value: _ReaderMenuAction.settings,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.tune, color: foregroundColor),
                        const SizedBox(width: 12),
                        Text('阅读设置', style: TextStyle(color: foregroundColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReaderMenuAction { chapters, settings }

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.bottomInset,
    required this.currentChapter,
    required this.totalChapters,
    required this.progress,
    required this.onPreviousChapter,
    required this.onNextChapter,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final double bottomInset;
  final int currentChapter;
  final int totalChapters;
  final double? progress;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  @override
  Widget build(BuildContext context) {
    final disabled = foregroundColor.withValues(alpha: 0.38);
    return Material(
      color: backgroundColor,
      elevation: 8,
      shadowColor: foregroundColor.withValues(alpha: 0.18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (progress != null)
            LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: foregroundColor.withValues(alpha: 0.12),
            ),
          SizedBox(
            height: 64,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextButton.icon(
                    onPressed: onPreviousChapter,
                    style: TextButton.styleFrom(
                      foregroundColor: foregroundColor,
                      disabledForegroundColor: disabled,
                    ),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一章'),
                  ),
                ),
                if (totalChapters > 0)
                  Text(
                    '$currentChapter / $totalChapters',
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onNextChapter,
                    style: TextButton.styleFrom(
                      foregroundColor: foregroundColor,
                      disabledForegroundColor: disabled,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一章'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}
