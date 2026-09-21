import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/book_grid_slivers.dart';
import '../../shared/widgets/state_views.dart';
import 'shelf_editor_controller.dart';
import 'widgets/shelf_folder_picker.dart';
import 'widgets/shelf_manage_sheet.dart';
import 'widgets/shelf_tile.dart';

/// 书架页：根目录（`parents` 为空）与任意层级文件夹共用同一个界面。
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key, this.parents = const <String>[]});

  /// 当前所在文件夹的完整路径（从根到当前层）。
  final List<String> parents;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  List<String> get _parents => widget.parents;

  String get _editorKey => shelfEditorKey(_parents);

  ShelfEditorController get _editor =>
      ref.read(shelfEditorProvider(_editorKey).notifier);

  ShelfEditorState get _state => ref.read(shelfEditorProvider(_editorKey));

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await _editor.save();
    if (!saved || !mounted) return;
    messenger.showText('书架已保存');
  }

  /// 放弃草稿；有改动时先确认，返回是否已经放弃。
  Future<bool> _discard() async {
    if (_state.draft == null) return true;
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot != null && _editor.isDirty(snapshot)) {
      final ok = await showAppConfirm(
        context: context,
        title: '放弃修改',
        message: '书架的改动尚未保存，离开将丢失这些修改。',
        confirmLabel: '放弃',
      );
      if (!ok || !mounted) return false;
    }
    _editor.discard();
    return true;
  }

  /// 跳到书架的某一层；有未保存改动时先确认。
  Future<void> _goToPath(List<String> path) async {
    if (_editor.isCurrentPath(path)) return;
    if (!await _discard() || !mounted) return;
    if (path.isEmpty) {
      context.go('/shelf');
      return;
    }
    context.go(
      Uri(
        path: '/shelf/folder',
        queryParameters: <String, List<String>>{'parent': path},
      ).toString(),
    );
  }

  ShelfManageCommand get _modeCommand => switch (_state.mode) {
    ShelfMode.browse => ShelfManageCommand.browse,
    ShelfMode.select => ShelfManageCommand.select,
    ShelfMode.drag => ShelfManageCommand.drag,
  };

  Future<void> _openManageSheet() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final draft = editor.effectiveDraft(snapshot);
    final folders = editor.selectedFolders(draft);
    final books = editor.selectedBooks(draft);
    final dirty = editor.isDirty(snapshot);
    final command = await ShelfManageSheet.show(
      context,
      activeMode: _modeCommand,
      commands: <ShelfManageCommand>[
        ShelfManageCommand.browse,
        ShelfManageCommand.drag,
        ShelfManageCommand.select,
        ShelfManageCommand.createFolder,
        if (folders.length == 1 && books.isEmpty)
          ShelfManageCommand.renameFolder,
        if (folders.isNotEmpty && books.isEmpty)
          ShelfManageCommand.deleteFolder,
        if (_state.selected.isNotEmpty) ShelfManageCommand.moveItems,
        if (_state.selected.isNotEmpty) ShelfManageCommand.removeItems,
        if (dirty) ShelfManageCommand.save,
        if (dirty) ShelfManageCommand.discard,
      ],
    );
    if (command == null || !mounted) return;
    await _runCommand(command);
  }

  Future<void> _runCommand(ShelfManageCommand command) async {
    switch (command) {
      case ShelfManageCommand.browse:
        _editor.setMode(ShelfMode.browse);
      case ShelfManageCommand.drag:
        _editor.setMode(ShelfMode.drag);
      case ShelfManageCommand.select:
        _editor.setMode(ShelfMode.select);
      case ShelfManageCommand.createFolder:
        await _createFolder();
      case ShelfManageCommand.renameFolder:
        await _renameFolder();
      case ShelfManageCommand.deleteFolder:
        await _deleteFolders();
      case ShelfManageCommand.moveItems:
        await _moveItems();
      case ShelfManageCommand.removeItems:
        await _removeItems();
      case ShelfManageCommand.save:
        await _save();
      case ShelfManageCommand.discard:
        await _discard();
    }
  }

  Future<void> _createFolder() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final draft = editor.effectiveDraft(snapshot);
    final name = await showAppTextPrompt(
      context: context,
      title: _parents.isEmpty
          ? '新建文件夹'
          : '在「${editor.folderTitle(draft, _parents.last)}」下新建文件夹',
      hint: '请输入文件夹名称',
    );
    if (name == null || !mounted) return;
    editor.createFolder(name);
  }

  Future<void> _renameFolder() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final folders = editor.selectedFolders(editor.effectiveDraft(snapshot));
    if (folders.length != 1) return;
    final folder = folders.single;
    final name = await showAppTextPrompt(
      context: context,
      title: '重命名文件夹',
      hint: '请输入文件夹名称',
      initial: folder.title,
    );
    if (name == null || !mounted) return;
    editor.renameFolder(folder.folderId!, name);
  }

  Future<void> _deleteFolders() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final folders = editor.selectedFolders(editor.effectiveDraft(snapshot));
    if (folders.isEmpty) return;
    final ok = await showAppConfirm(
      context: context,
      title: '删除文件夹',
      message: '将删除所选的 ${folders.length} 个文件夹，其中的内容会移到上一层。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    editor.deleteFolders(folders);
  }

  Future<void> _moveItems() async {
    final snapshot = ref.read(shelfProvider).value;
    final selected = _state.selected;
    if (snapshot == null || selected.isEmpty) return;
    final editor = _editor;
    final target = await ShelfFolderPicker.show(
      context,
      draft: editor.effectiveDraft(snapshot),
      movingKeys: Set<String>.of(selected),
      currentParents: _parents,
    );
    if (target == null || !mounted) return;
    editor.moveItems(
      keys: Set<String>.of(selected),
      destination: target.parents,
      newFolderName: target.newFolderName,
    );
  }

  Future<void> _removeItems() async {
    final snapshot = ref.read(shelfProvider).value;
    final selected = _state.selected;
    if (snapshot == null || selected.isEmpty) return;
    final editor = _editor;
    final draft = editor.effectiveDraft(snapshot);
    final hasFolder = editor.selectedFolders(draft).isNotEmpty;
    final ok = await showAppConfirm(
      context: context,
      title: '移出书架',
      message: hasFolder
          ? '所选文件夹及其中的 ${shelfSelectionBookCount(draft, selected)} 本书会一起移出书架，阅读记录不受影响。'
          : '将从书架移出 ${shelfSelectionBookCount(draft, selected)} 本书，阅读记录不受影响。',
      confirmLabel: '移出',
    );
    if (!ok || !mounted) return;
    editor.removeItems(Set<String>.of(selected));
  }

  void _openFolder(String folderId) {
    final uri = Uri(
      path: '/shelf/folder',
      queryParameters: <String, List<String>>{
        'parent': <String>[..._parents, folderId],
      },
    );
    context.push(uri.toString());
  }

  void _openBook(BookListItem book) {
    context.push('/book/${book.id}');
  }

  Widget _banner(
    String message, {
    required VoidCallback onAction,
    IconData actionIcon = Icons.close,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 19 / 14,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onAction,
            child: Icon(actionIcon, size: 20, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 路径导航：点任意一层直接跳到那一层。
  Widget _breadcrumb(ShelfDraft draft) {
    final colors = Theme.of(context).colorScheme;
    Widget crumb(String label, List<String> path, {required bool active}) =>
        InkWell(
          onTap: active ? null : () => _goToPath(path),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 19 / 14,
                color: active ? colors.onSurface : colors.primary,
              ),
            ),
          ),
        );

    final crumbs = <Widget>[crumb('我的书架', const <String>[], active: false)];
    for (var depth = 0; depth < _parents.length; depth += 1) {
      crumbs
        ..add(
          Icon(Icons.chevron_right, size: 16, color: colors.onSurfaceVariant),
        )
        ..add(
          crumb(
            _editor.folderTitle(draft, _parents[depth]),
            _parents.sublist(0, depth + 1),
            active: depth == _parents.length - 1,
          ),
        );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
    );
  }

  Widget _selectionSummary(
    ShelfDraft draft,
    ShelfEditorState editor,
    List<ShelfItem> siblings,
  ) {
    final colors = Theme.of(context).colorScheme;
    final books = shelfSelectionBookCount(draft, editor.selected);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '已选择 ${editor.selected.length} 项 · 含 $books 本书',
              style: TextStyle(fontSize: 14, color: colors.onSurface),
            ),
          ),
          TextButton(
            onPressed: () => _editor.selectAll(siblings),
            child: const Text('全选'),
          ),
          TextButton(
            onPressed: () => _editor.setMode(ShelfMode.browse),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authenticated = ref.watch(authSnapshotProvider).isAuthenticated;
    final async = ref.watch(shelfProvider);
    final editor = ref.watch(shelfEditorProvider(_editorKey));
    final snapshot = async.value;
    final controller = _editor;
    final dirty = snapshot != null && controller.isDirty(snapshot);
    final draft = snapshot == null ? null : controller.effectiveDraft(snapshot);
    final title = _parents.isEmpty || draft == null
        ? '书架'
        : controller.folderTitle(draft, _parents.last);

    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discarded = await _discard();
        if (!discarded || !context.mounted) return;
        if (context.canPop()) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: <Widget>[
            if (dirty && !editor.saving)
              TextButton(onPressed: () => _discard(), child: const Text('取消')),
            if (dirty)
              editor.saving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    )
                  : TextButton(onPressed: _save, child: const Text('保存')),
            IconButton(
              tooltip: '管理书架',
              onPressed: snapshot == null ? null : _openManageSheet,
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        body: !authenticated
            ? EmptyStateView(
                icon: Icons.lock_outline,
                title: '登录后查看书架',
                description: '登录轻书架账号即可同步书架与阅读进度。',
                actionLabel: '去登录',
                onAction: () => context.go('/sign-in'),
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(shelfProvider.notifier).reload(),
                child: _body(async, editor, snapshot, draft),
              ),
      ),
    );
  }

  Widget _body(
    AsyncValue<ShelfSnapshot?> async,
    ShelfEditorState editor,
    ShelfSnapshot? snapshot,
    ShelfDraft? draft,
  ) {
    final media = MediaQuery.sizeOf(context);
    final layout = BookGridLayout.of(media.width);

    if (snapshot == null || draft == null) {
      if (async.hasError) {
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorStateView(
                message: describeShelfError(async.error!),
                onRetry: () => ref.read(shelfProvider.notifier).reload(),
              ),
            ),
          ],
        );
      }
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          bookGridSkeletonSliver(
            layout: layout,
            count: layout.skeletonCount(media.height, headerOffset: 120),
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              20,
              BookGridLayout.horizontalPadding,
              20,
            ),
          ),
        ],
      );
    }

    final level = _editor.level(draft);
    final siblings = level.siblings;
    final refreshError = async.hasError
        ? describeShelfError(async.error!)
        : null;
    final editorError = editor.error;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            BookGridLayout.horizontalPadding,
            20,
            BookGridLayout.horizontalPadding,
            0,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              if (_parents.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _breadcrumb(draft),
                ),
              if (editorError != null)
                _banner(editorError, onAction: () => _editor.clearError()),
              if (refreshError != null)
                _banner(
                  '刷新失败：$refreshError',
                  onAction: () => ref.read(shelfProvider.notifier).reload(),
                  actionIcon: Icons.refresh,
                ),
              if (editor.mode == ShelfMode.select)
                _selectionSummary(draft, editor, siblings),
              if (editor.mode == ShelfMode.drag)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '长按书籍或文件夹拖动到目标位置，完成后点击保存。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (siblings.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateView(
              icon: _parents.isEmpty
                  ? Icons.collections_bookmark_outlined
                  : Icons.folder_open_outlined,
              title: _parents.isEmpty ? '书架还是空的' : '这个文件夹是空的',
              description: _parents.isEmpty
                  ? '在书籍详情页点击“加入书架”，之后就能在这里找到它。'
                  : '把书籍移动到这个文件夹后会显示在这里。',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              0,
              BookGridLayout.horizontalPadding,
              32,
            ),
            sliver: SliverGrid(
              gridDelegate: layout.tileGridDelegate(
                mainAxisSpacing: editor.mode == ShelfMode.drag ? 18 : null,
              ),
              delegate: IdentityChildDelegate<ShelfItem>(
                items: level.siblings,
                revision: (level, layout.tileWidth),
                itemBuilder: (_, item, index) => ShelfTile(
                  editorKey: _editorKey,
                  item: item,
                  index: index,
                  siblings: level.siblings,
                  folder: item.isBook
                      ? null
                      : level.folderPreviews[item.folderId],
                  tileWidth: layout.tileWidth,
                  onOpenBook: _openBook,
                  onOpenFolder: _openFolder,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
