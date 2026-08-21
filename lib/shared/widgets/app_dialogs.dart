import 'package:flutter/material.dart';

/// 全站统一的对话框与轻提示入口。任何界面都不该再手写 `AlertDialog` 骨架。

Future<void> showAppAlert({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = '好',
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(title),
    content: message == null ? null : Text(message),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: Text(confirmLabel),
      ),
    ],
  ),
);

/// 二次确认弹窗；`destructive` 用于退出登录、删除一类的破坏性操作。
Future<bool> showAppConfirm({
  required BuildContext context,
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
  bool barrierDismissible = true,
}) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: colors.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 单行文本输入弹窗；返回 null 表示取消或只输入了空白。
Future<String?> showAppTextPrompt({
  required BuildContext context,
  required String title,
  required String hint,
  String initial = '',
  String confirmLabel = '确定',
  String cancelLabel = '取消',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  controller.dispose();
  final text = result?.trim() ?? '';
  return text.isEmpty ? null : text;
}

/// 选项列表弹窗；返回 null 表示取消。
Future<T?> showAppChoice<T extends Object>({
  required BuildContext context,
  required String title,
  required List<(String label, T value)> options,
}) => showDialog<T>(
  context: context,
  builder: (dialogContext) => SimpleDialog(
    title: Text(title),
    children: <Widget>[
      for (final option in options)
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(option.$2),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(option.$1),
          ),
        ),
    ],
  ),
);

/// 轻提示：同一时间只留一条，连续操作不会排队堆积。
void showAppSnackBar(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showText(message);

extension AppSnackBarMessenger on ScaffoldMessengerState {
  /// await 之后 `context` 可能已失效，先拿到 messenger 再调这个。
  void showText(String message) {
    hideCurrentSnackBar();
    showSnackBar(SnackBar(content: Text(message)));
  }
}
