import 'package:flutter/material.dart';

/// 全站唯一的阅读点击热区：沿 [axis] 两端各 30% 翻页，中间 40% 切换工具栏。
///
/// 带 [child] 时作为正文的父节点（正文里的链接/图片先拿到点击）；不带 [child] 时
/// 铺在内容之上，用于 PhotoView 这类自己吃掉点击的子树。
class ReaderTapZoneLayer extends StatelessWidget {
  const ReaderTapZoneLayer({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleChrome,
    this.axis = Axis.horizontal,
    this.reversed = false,
    this.child,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleChrome;
  final Axis axis;

  /// 右向左阅读时翻页方向对调。
  final bool reversed;

  final Widget? child;

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
      child: child,
    ),
  );
}
