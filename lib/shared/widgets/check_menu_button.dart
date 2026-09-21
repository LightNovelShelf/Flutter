import 'package:flutter/material.dart';

/// 单选菜单的一项。
@immutable
class CheckMenuEntry<T> {
  const CheckMenuEntry({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

/// 标题栏上的单选下拉菜单：图标 + 文字 + 当前项打勾。
///
/// 自己算宽度并用 `constraints` 定死，是因为 `PopupMenuButton` 的面板宽度默认要过一层
/// `IntrinsicWidth(stepWidth: 56)`，内容宽度会被向上取整到 56 的倍数，勾后面就空出一截。
class CheckMenuButton<T> extends StatelessWidget {
  const CheckMenuButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.entries,
    required this.onSelected,
  });

  final String tooltip;

  /// 标题栏上的按钮图标。
  final Widget icon;
  final T value;
  final List<CheckMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  /// 菜单项左右内边距，与 `PopupMenuItem` 的默认值一致。
  static const double _itemPadding = 16;
  static const double _leadingSize = 20;
  static const double _leadingGap = 12;
  static const double _checkGap = 8;
  static const double _checkSize = 18;

  double _width(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final entry in entries) {
      final painter = TextPainter(
        text: TextSpan(text: entry.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      widest = widest > painter.width ? widest : painter.width;
    }
    return _itemPadding * 2 +
        _leadingSize +
        _leadingGap +
        widest +
        _checkGap +
        _checkSize;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: icon,
      initialValue: value,
      position: PopupMenuPosition.under,
      constraints: BoxConstraints.tightFor(width: _width(context)),
      onSelected: onSelected,
      itemBuilder: (_) => <PopupMenuEntry<T>>[
        for (final entry in entries)
          PopupMenuItem<T>(
            value: entry.value,
            child: Row(
              children: <Widget>[
                Icon(entry.icon, size: _leadingSize),
                const SizedBox(width: _leadingGap),
                Expanded(child: Text(entry.label)),
                if (entry.value == value) ...<Widget>[
                  const SizedBox(width: _checkGap),
                  Icon(Icons.check, size: _checkSize, color: colors.primary),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
