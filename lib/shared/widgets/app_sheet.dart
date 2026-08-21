import 'package:flutter/material.dart';

/// 全站统一的可拖拽底部抽屉：吸附在 [initialSize] 与全屏两档。
Future<T?> showDraggableSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
  double initialSize = 0.6,
  double minSize = 0.4,
  bool showDragHandle = false,
  bool useRootNavigator = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: useRootNavigator,
  showDragHandle: showDragHandle,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: initialSize,
    minChildSize: minSize,
    maxChildSize: 1,
    snap: true,
    snapSizes: <double>[initialSize, 1],
    builder: builder,
  ),
);

/// 抽屉标题行：主题色图标 + 粗体标题。
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.icon,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 8),
  });

  final IconData icon;
  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: colors.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              height: 22 / 17,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
