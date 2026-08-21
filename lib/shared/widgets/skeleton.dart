import 'package:flutter/material.dart';

/// 骨架屏占位块：全站统一的灰底圆角矩形。
/// `widthFactor` 按父级宽度的比例取宽，与 `width` 二选一。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.widthFactor,
    this.radius = 8,
  });

  final double height;
  final double? width;
  final double? widthFactor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: box,
    );
  }
}
