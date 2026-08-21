import 'package:flutter/material.dart';

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
