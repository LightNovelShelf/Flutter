import 'package:flutter/material.dart';

/// 输入框共用的文字样式与装饰，保证密码框与普通框视觉一致。
TextStyle authFieldTextStyle(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 17,
    );

InputDecoration authFieldDecoration(
  BuildContext context, {
  required String hintText,
}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: colors.outlineVariant, width: 1),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 17),
    filled: true,
    fillColor: colors.surfaceContainer,
    isDense: true,
    // 高度只能由竖向内边距给，InputDecorator 按自身算出的容器高度绘制填充与边框，
    // 外层 SizedBox 撑不开。17 号字行高 26 加上下各 13 得 52，minHeight 用于字号放大时兜底。
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    constraints: const BoxConstraints(minHeight: 52),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.primary, width: 1),
    ),
  );
}
