import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

/// 常驻的章节 / 页码信息；工具栏展开时淡出，避免与底栏重叠。
class ReaderStatusPills extends StatelessWidget {
  const ReaderStatusPills({
    super.key,
    required this.visible,
    required this.foregroundColor,
    required this.currentChapter,
    required this.totalChapters,
    required this.currentPage,
    required this.totalPages,
  });

  final bool visible;
  final Color foregroundColor;
  final int currentChapter;
  final int totalChapters;
  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: visible ? 1 : 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ReaderStatusPill(
            icon: Icons.book_outlined,
            value: '$currentChapter/$totalChapters',
            foregroundColor: foregroundColor,
          ),
          const SizedBox(width: 8),
          _ReaderStatusPill(
            icon: Icons.menu_book_outlined,
            value: '$currentPage/$totalPages',
            foregroundColor: foregroundColor,
          ),
        ],
      ),
    ),
  );
}

class _ReaderStatusPill extends StatelessWidget {
  const _ReaderStatusPill({
    required this.icon,
    required this.value,
    required this.foregroundColor,
  });

  final IconData icon;
  final String value;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = foregroundColor.withValues(alpha: 0.78);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foregroundColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 14 / 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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

/// 点击热区：两端 30% 翻页，中间切换工具栏。
class ReaderTapZoneLayer extends StatelessWidget {
  const ReaderTapZoneLayer({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleChrome,
    this.axis = Axis.horizontal,
    this.reversed = false,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleChrome;
  final Axis axis;

  /// 右向左阅读时翻页方向对调。
  final bool reversed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final horizontal = axis == Axis.horizontal;
        final position = horizontal
            ? details.localPosition.dx
            : details.localPosition.dy;
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        if (extent <= 0) return;
        if (position <= extent * 0.3) {
          (reversed ? onNext : onPrevious)();
        } else if (position >= extent * 0.7) {
          (reversed ? onPrevious : onNext)();
        } else {
          onToggleChrome();
        }
      },
    ),
  );
}
