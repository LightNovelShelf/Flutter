import 'package:flutter/material.dart';

/// 漫画整页加载失败的占位：铺满页面区域的点击重试块。
class ComicRetryTile extends StatelessWidget {
  const ComicRetryTile({
    super.key,
    required this.width,
    required this.height,
    required this.onRetry,
  });

  final double width;
  final double height;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onRetry,
          child: Center(
            child: Text(
              '加载失败，点击重试',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
