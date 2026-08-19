import 'package:flutter/material.dart';

/// 书架管理面板可执行的命令；具体行为由书架页实现。
enum ShelfManageCommand {
  browse,
  drag,
  select,
  createFolder,
  renameFolder,
  deleteFolder,
  moveBooks,
  removeItems,
  save,
  discard,
}

class _ShelfCommandSpec {
  const _ShelfCommandSpec(this.icon, this.label, {this.destructive = false});

  final IconData icon;
  final String label;
  final bool destructive;
}

_ShelfCommandSpec _specFor(ShelfManageCommand command, {required bool active}) =>
    switch (command) {
      ShelfManageCommand.browse => _ShelfCommandSpec(
          Icons.touch_app_outlined,
          active ? '正在浏览' : '浏览书架',
        ),
      ShelfManageCommand.drag => _ShelfCommandSpec(
          Icons.swap_vert,
          active ? '排序中' : '拖动排序',
        ),
      ShelfManageCommand.select => _ShelfCommandSpec(
          Icons.checklist,
          active ? '正在选择' : '选择条目',
        ),
      ShelfManageCommand.createFolder =>
        const _ShelfCommandSpec(Icons.create_new_folder_outlined, '新建文件夹'),
      ShelfManageCommand.renameFolder =>
        const _ShelfCommandSpec(Icons.drive_file_rename_outline, '重命名文件夹'),
      ShelfManageCommand.deleteFolder => const _ShelfCommandSpec(
          Icons.folder_delete_outlined,
          '删除文件夹',
          destructive: true,
        ),
      ShelfManageCommand.moveBooks =>
        const _ShelfCommandSpec(Icons.drive_file_move_outlined, '移动到文件夹'),
      ShelfManageCommand.removeItems => const _ShelfCommandSpec(
          Icons.delete_outline,
          '移出书架',
          destructive: true,
        ),
      ShelfManageCommand.save => const _ShelfCommandSpec(Icons.check, '保存更改'),
      ShelfManageCommand.discard => const _ShelfCommandSpec(
          Icons.close,
          '放弃更改',
          destructive: true,
        ),
    };

/// 书架管理底部面板：选中的命令通过 `Navigator.pop` 回传给书架页执行。
class ShelfManageSheet extends StatelessWidget {
  const ShelfManageSheet({
    super.key,
    required this.commands,
    required this.activeMode,
  });

  final List<ShelfManageCommand> commands;

  /// 当前交互模式对应的命令，用于把该行标成「正在…」。
  final ShelfManageCommand activeMode;

  static Future<ShelfManageCommand?> show(
    BuildContext context, {
    required List<ShelfManageCommand> commands,
    required ShelfManageCommand activeMode,
  }) =>
      showModalBottomSheet<ShelfManageCommand>(
        context: context,
        builder: (_) => ShelfManageSheet(
          commands: commands,
          activeMode: activeMode,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.tune, size: 22, color: colors.primary),
                const SizedBox(width: 10),
                Text('管理书架', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final command in commands)
                      _CommandRow(
                        spec: _specFor(command, active: command == activeMode),
                        onTap: () => Navigator.of(context).pop(command),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.spec, required this.onTap});

  final _ShelfCommandSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = spec.destructive ? colors.error : colors.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Icon(spec.icon, size: 21, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                spec.label,
                style: TextStyle(
                  fontSize: 17,
                  height: 22 / 17,
                  color: spec.destructive ? colors.error : colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
