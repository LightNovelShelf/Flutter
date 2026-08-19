import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';

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

  static const Duration _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: _duration,
        opacity: visible ? 1 : 0,
        child: Stack(
          children: <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: _duration,
                offset: visible ? Offset.zero : const Offset(0, -1),
                child: _TopBar(
                  title: title,
                  backgroundColor: backgroundColor,
                  foregroundColor: foregroundColor,
                  topInset: padding.top,
                  onOpenChapters: onOpenChapters,
                  onOpenSettings: onOpenSettings,
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: _duration,
                offset: visible ? Offset.zero : const Offset(0, 1),
                child: _BottomBar(
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
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.topInset,
    required this.onOpenChapters,
    required this.onOpenSettings,
  });

  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final double topInset;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Material(
        color: backgroundColor,
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
          child: SizedBox(
            height: 56,
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  color: foregroundColor,
                  tooltip: '返回',
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onOpenChapters,
                  icon: const Icon(Icons.menu_book_outlined),
                  color: foregroundColor,
                  tooltip: '目录',
                ),
                IconButton(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                  color: foregroundColor,
                  tooltip: '设置',
                ),
              ],
            ),
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (progress != null)
            LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: foregroundColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          SizedBox(
            height: 56,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: onPreviousChapter,
                    style: TextButton.styleFrom(
                      foregroundColor: foregroundColor,
                      disabledForegroundColor: disabled,
                    ),
                    child: const Text('上一章'),
                  ),
                ),
                if (totalChapters > 0)
                  Text(
                    '$currentChapter / $totalChapters',
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 13,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                Expanded(
                  child: TextButton(
                    onPressed: onNextChapter,
                    style: TextButton.styleFrom(
                      foregroundColor: foregroundColor,
                      disabledForegroundColor: disabled,
                    ),
                    child: const Text('下一章'),
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
            final extent =
                horizontal ? constraints.maxWidth : constraints.maxHeight;
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

/// 全屏图片预览：捏合缩放，点击关闭。
Future<void> showReaderImagePreview(BuildContext context, String url) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.96),
        pageBuilder: (context, _, _) => _ReaderImagePreview(url: url),
      ),
    );

class _ReaderImagePreview extends StatelessWidget {
  const _ReaderImagePreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
            PhotoView(
              imageProvider: CachedNetworkImageProvider(url),
              backgroundDecoration:
                  const BoxDecoration(color: Colors.transparent),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 6,
              onTapUp: (context, _, _) => Navigator.of(context).pop(),
              loadingBuilder: (context, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorBuilder: (context, _, _) => const Center(
                child: Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                color: Colors.white,
                tooltip: '关闭',
              ),
            ),
          ],
        ),
      );
}
