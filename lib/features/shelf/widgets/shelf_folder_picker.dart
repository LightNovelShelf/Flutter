import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../data/repositories/shelf_draft.dart';

/// 移动目标：`parents` 是目标层的完整路径，[newFolderName] 非空表示要先在该层新建文件夹。
@immutable
class ShelfMoveTarget {
  const ShelfMoveTarget({required this.parents, this.newFolderName});

  final List<String> parents;
  final String? newFolderName;
}

/// 移动到文件夹：逐层下钻选目标层，可在任意层新建子文件夹。
class ShelfFolderPicker extends StatefulWidget {
  const ShelfFolderPicker({
    super.key,
    required this.draft,
    required this.movingKeys,
    required this.currentParents,
  });

  final ShelfDraft draft;

  /// 待移动条目的 key，其中的文件夹不能作为目标。
  final Set<String> movingKeys;

  /// 这些条目现在所在的层。
  final List<String> currentParents;

  static Future<ShelfMoveTarget?> show(
    BuildContext context, {
    required ShelfDraft draft,
    required Set<String> movingKeys,
    required List<String> currentParents,
  }) => showModalBottomSheet<ShelfMoveTarget>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ShelfFolderPicker(
      draft: draft,
      movingKeys: movingKeys,
      currentParents: currentParents,
    ),
  );

  @override
  State<ShelfFolderPicker> createState() => _ShelfFolderPickerState();
}

class _ShelfFolderPickerState extends State<ShelfFolderPicker> {
  final TextEditingController _name = TextEditingController();
  List<String> _browse = const <String>[];
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  late final Set<String> _blocked = <String>{
    for (final item in widget.draft.items)
      if (!item.isBook && widget.movingKeys.contains(item.key)) item.folderId!,
  };

  bool get _sameLevel {
    if (_browse.length != widget.currentParents.length) return false;
    for (var index = 0; index < _browse.length; index += 1) {
      if (_browse[index] != widget.currentParents[index]) return false;
    }
    return true;
  }

  String _titleOf(String id) {
    final title = shelfFolderById(widget.draft, id)?.title.trim() ?? '';
    return title.isEmpty ? '未命名文件夹' : title;
  }

  String get _currentTitle =>
      _browse.isEmpty ? '书架根目录' : _titleOf(_browse.last);

  List<ShelfItem> get _children => shelfItemsAtPath(
    widget.draft,
    _browse,
  ).where((item) => !item.isBook).toList();

  /// 当前层每个子文件夹的「直接子文件夹数 / 子树书籍数」。
  Map<String, (int folders, int books)> _counts(List<ShelfItem> children) {
    final counts = <String, (int, int)>{
      for (final child in children) child.folderId!: (0, 0),
    };
    final childDepth = _browse.length + 1;
    for (final item in widget.draft.items) {
      if (item.parents.length < childDepth) continue;
      final current = counts[item.parents[_browse.length]];
      if (current == null) continue;
      counts[item.parents[_browse.length]] = item.isBook
          ? (current.$1, current.$2 + 1)
          : (
              item.parents.length == childDepth ? current.$1 + 1 : current.$1,
              current.$2,
            );
    }
    return counts;
  }

  void _submitExisting() =>
      Navigator.of(context)
          .pop(ShelfMoveTarget(parents: List<String>.of(_browse)));

  void _submitNew() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      ShelfMoveTarget(parents: List<String>.of(_browse), newFolderName: name),
    );
  }

  Widget _breadcrumb() {
    final colors = Theme.of(context).colorScheme;
    final crumbs = <Widget>[
      _crumb('书架', const <String>[], active: _browse.isEmpty),
    ];
    for (var depth = 0; depth < _browse.length; depth += 1) {
      crumbs
        ..add(
          Icon(Icons.chevron_right, size: 16, color: colors.onSurfaceVariant),
        )
        ..add(
          _crumb(
            _titleOf(_browse[depth]),
            _browse.sublist(0, depth + 1),
            active: depth == _browse.length - 1,
          ),
        );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
    );
  }

  Widget _crumb(String label, List<String> path, {required bool active}) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: active ? null : () => setState(() => _browse = path),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: active ? colors.onSurface : colors.primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final children = _children;
    final counts = _counts(children);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '移动 ${widget.movingKeys.length} 项到...',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _breadcrumb(),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: children.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Text(
                        '这一层还没有子文件夹',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: children.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final folder = children[index];
                        final id = folder.folderId!;
                        final count = counts[id] ?? (0, 0);
                        final blocked = _blocked.contains(id);
                        return ListTile(
                          enabled: !blocked,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            _titleOf(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            blocked
                                ? '正在移动这个文件夹'
                                : '${count.$1} 个文件夹 · ${count.$2} 本书',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(
                            () => _browse = <String>[..._browse, id],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            if (_creating)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _name,
                        autofocus: true,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: '在「$_currentTitle」下新建',
                        ),
                        onSubmitted: (_) => _submitNew(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _submitNew,
                      child: const Text('创建并移入'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => setState(() => _creating = !_creating),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('新建子文件夹'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: _sameLevel ? null : _submitExisting,
                    child: Text(
                      _sameLevel ? '已在「$_currentTitle」' : '移动到「$_currentTitle」',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
