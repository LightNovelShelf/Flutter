import 'package:flutter/material.dart';

/// 未读角标：0 不显示，超过 99 显示 99+。
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: child,
  );
}
