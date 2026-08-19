import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/widgets/book_cover_grid_item.dart';
import '../../shared/widgets/state_views.dart';
import 'widgets/shelf_folder_tile.dart';
import 'widgets/shelf_manage_sheet.dart';

enum _ShelfMode { browse, select, drag }

/// 书架错误文案：认证/网络单独提示，其余沿用服务端消息。
String describeShelfError(Object error, {String fallback = '书架暂时不可用。'}) {
  if (error is ArgumentError) {
    return error.message?.toString() ?? fallback;
  }
  if (error is ApiError) {
    return switch (error.category) {
      ApiErrorCategory.auth => '登录状态已过期，请重新登录后继续。',
      ApiErrorCategory.network => '网络连接不可用，请检查后重试。',
      _ => error.message.trim().isEmpty ? fallback : error.message,
    };
  }
  return describeShelfError(toApiError(error), fallback: fallback);
}

/// 书架页：根目录（`parents` 为空）与任意层级文件夹共用同一个界面。
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({super.key, this.parents = const <String>[]});

  /// 当前所在文件夹的完整路径（从根到当前层）。
  final List<String> parents;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  /// 非空表示正在编辑；保存或放弃后回到快照。
  ShelfDraft? _draft;
  final Set<String> _selected = <String>{};
  _ShelfMode _mode = _ShelfMode.browse;
  String? _editorError;
  bool _saving = false;

  List<String> get _parents => widget.parents;

  static String _now() => DateTime.now().toUtc().toIso8601String();

  ShelfDraft _effectiveDraft(ShelfSnapshot snapshot) =>
      _draft ?? snapshot.toDraft();

  bool _isDirty(ShelfSnapshot snapshot) {
    final draft = _draft;
    return draft != null && shelfDraftHasChanges(snapshot, draft);
  }

  ShelfItem? _findFolder(ShelfDraft draft, String id) {
    for (final item in draft.items) {
      if (!item.isBook && item.folderId == id) return item;
    }
    return null;
  }

  String _folderTitle(ShelfDraft draft, String id) {
    final folder = _findFolder(draft, id);
    if (folder == null) return '文件夹已不存在';
    final title = folder.title.trim();
    return title.isEmpty ? '未命名文件夹' : title;
  }

  String _pathLabel(ShelfDraft draft, List<String> path) => path.isEmpty
      ? '根文件夹'
      : path.map((id) => _folderTitle(draft, id)).join(' / ');

  List<ShelfItem> _selectedFolders(ShelfDraft draft) => draft.items
      .where((item) => !item.isBook && _selected.contains(item.key))
      .toList();

  List<ShelfItem> _selectedBooks(ShelfDraft draft) => draft.items
      .where((item) => item.isBook && _selected.contains(item.key))
      .toList();

  /// 编辑一律落在草稿上；校验失败只弹横幅，草稿不动。
  void _applyMutation(ShelfDraft Function(ShelfDraft draft) apply) {
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot == null || _saving) return;
    try {
      final next = apply(_effectiveDraft(snapshot));
      setState(() {
        _draft = next;
        _editorError = null;
      });
    } catch (error) {
      setState(() => _editorError = describeShelfError(error, fallback: '书架操作失败。'));
    }
  }

  void _setMode(_ShelfMode mode) {
    setState(() {
      _mode = mode;
      // 离开多选或进入排序时清空选择，避免选中项跨模式残留。
      if (mode != _ShelfMode.select) _selected.clear();
    });
  }

  void _toggleSelection(ShelfItem item) {
    setState(() {
      if (!_selected.remove(item.key)) _selected.add(item.key);
      if (_selected.isEmpty && _mode == _ShelfMode.select) {
        _mode = _ShelfMode.browse;
      }
    });
  }

  void _beginSelection(ShelfItem item) {
    setState(() {
      _mode = _ShelfMode.select;
      _selected
        ..clear()
        ..add(item.key);
    });
  }

  void _reorder(List<ShelfItem> siblings, int from, int to) {
    if (from == to) return;
    final keys = siblings.map((item) => item.key).toList();
    final moved = keys.removeAt(from);
    keys.insert(to, moved);
    _applyMutation(
      (draft) => reorderShelfSiblings(
        draft,
        parents: _parents,
        orderedKeys: keys,
        now: _now(),
      ),
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() {
      _saving = true;
      _editorError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shelfProvider.notifier).save(draft);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = null;
        _mode = _ShelfMode.browse;
        _selected.clear();
      });
      messenger.showSnackBar(const SnackBar(content: Text('书架已保存')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editorError = describeShelfError(error, fallback: '保存失败，请稍后重试。');
      });
    }
  }

  /// 放弃草稿；有改动时先确认，返回是否已经放弃。
  Future<bool> _discard() async {
    if (_draft == null) return true;
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot != null && _isDirty(snapshot)) {
      final ok = await _confirm(
        title: '放弃修改',
        message: '书架的改动尚未保存，离开将丢失这些修改。',
        confirmLabel: '放弃',
      );
      if (!ok || !mounted) return false;
    }
    setState(() {
      _draft = null;
      _editorError = null;
      _mode = _ShelfMode.browse;
      _selected.clear();
    });
    return true;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String initial = '',
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
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = result?.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  /// 选择移动目标；返回空列表代表根文件夹，返回 null 代表取消。
  Future<List<String>?> _pickDestination(ShelfDraft draft) {
    final destinations = <(String label, List<String> path)>[
      if (_parents.isNotEmpty) ('根文件夹', const <String>[]),
      for (final folder in shelfFolderPaths(draft))
        if (!_isCurrentPath(folder.path)) (_pathLabel(draft, folder.path), folder.path),
    ];
    if (destinations.isEmpty) {
      setState(() => _editorError = '还没有可用的目标文件夹，请先新建一个。');
      return Future<List<String>?>.value();
    }
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: <Widget>[
          for (final destination in destinations)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(destination.$2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(destination.$1),
              ),
            ),
        ],
      ),
    );
  }

  bool _isCurrentPath(List<String> path) {
    if (path.length != _parents.length) return false;
    for (var index = 0; index < path.length; index += 1) {
      if (path[index] != _parents[index]) return false;
    }
    return true;
  }

  ShelfManageCommand get _modeCommand => switch (_mode) {
        _ShelfMode.browse => ShelfManageCommand.browse,
        _ShelfMode.select => ShelfManageCommand.select,
        _ShelfMode.drag => ShelfManageCommand.drag,
      };

  Future<void> _openManageSheet() async {
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot == null) return;
    final draft = _effectiveDraft(snapshot);
    final folders = _selectedFolders(draft);
    final books = _selectedBooks(draft);
    final dirty = _isDirty(snapshot);
    final command = await ShelfManageSheet.show(
      context,
      activeMode: _modeCommand,
      commands: <ShelfManageCommand>[
        ShelfManageCommand.browse,
        ShelfManageCommand.drag,
        ShelfManageCommand.select,
        ShelfManageCommand.createFolder,
        if (folders.length == 1 && books.isEmpty) ShelfManageCommand.renameFolder,
        if (folders.isNotEmpty && books.isEmpty) ShelfManageCommand.deleteFolder,
        if (books.isNotEmpty && folders.isEmpty) ShelfManageCommand.moveBooks,
        if (_selected.isNotEmpty) ShelfManageCommand.removeItems,
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
        _setMode(_ShelfMode.browse);
      case ShelfManageCommand.drag:
        _setMode(_ShelfMode.drag);
      case ShelfManageCommand.select:
        _setMode(_ShelfMode.select);
      case ShelfManageCommand.createFolder:
        await _createFolder();
      case ShelfManageCommand.renameFolder:
        await _renameFolder();
      case ShelfManageCommand.deleteFolder:
        await _deleteFolders();
      case ShelfManageCommand.moveBooks:
        await _moveBooks();
      case ShelfManageCommand.removeItems:
        await _removeItems();
      case ShelfManageCommand.save:
        await _save();
      case ShelfManageCommand.discard:
        await _discard();
    }
  }

  Future<void> _createFolder() async {
    final name = await _promptText(title: '新建文件夹', hint: '请输入文件夹名称');
    if (name == null || !mounted) return;
    // 服务端的书架结构里文件夹只有根层级，新建的一律落在根目录。
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _applyMutation(
      (draft) => createShelfFolder(draft, id: id, title: name, now: _now()),
    );
  }

  Future<void> _renameFolder() async {
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot == null) return;
    final folders = _selectedFolders(_effectiveDraft(snapshot));
    if (folders.length != 1) return;
    final folder = folders.single;
    final name = await _promptText(
      title: '重命名文件夹',
      hint: '请输入文件夹名称',
      initial: folder.title,
    );
    if (name == null || !mounted) return;
    _applyMutation(
      (draft) => renameShelfFolder(
        draft,
        id: folder.folderId!,
        title: name,
        now: _now(),
      ),
    );
  }

  Future<void> _deleteFolders() async {
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot == null) return;
    final folders = _selectedFolders(_effectiveDraft(snapshot));
    if (folders.isEmpty) return;
    final ok = await _confirm(
      title: '删除文件夹',
      message: '将删除所选的 ${folders.length} 个文件夹，其中的书籍会移回书架根目录。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    _applyMutation((draft) {
      var next = draft;
      final now = _now();
      for (final folder in folders) {
        next = deleteShelfFolder(next, id: folder.folderId!, now: now);
      }
      return next;
    });
    setState(_selected.clear);
  }

  Future<void> _moveBooks() async {
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot == null) return;
    final draft = _effectiveDraft(snapshot);
    final books = _selectedBooks(draft);
    if (books.isEmpty) return;
    final destination = await _pickDestination(draft);
    if (destination == null || !mounted) return;
    _applyMutation(
      (current) => moveShelfBooks(
        current,
        bookIds: books.map((item) => item.bookId!).toList(),
        destination: destination,
        now: _now(),
      ),
    );
    setState(_selected.clear);
  }

  Future<void> _removeItems() async {
    final snapshot = ref.read(shelfProvider).valueOrNull;
    if (snapshot == null || _selected.isEmpty) return;
    final draft = _effectiveDraft(snapshot);
    final hasFolder = _selectedFolders(draft).isNotEmpty;
    final ok = await _confirm(
      title: '移出书架',
      message: hasFolder
          ? '所选文件夹会被删除，其中的书籍将移回书架根目录。'
          : '将从书架移出 ${shelfSelectionBookCount(draft, _selected)} 本书，阅读记录不受影响。',
      confirmLabel: '移出',
    );
    if (!ok || !mounted) return;
    final keys = Set<String>.of(_selected);
    _applyMutation(
      (current) => removeShelfItems(current, keys: keys, now: _now()),
    );
    setState(_selected.clear);
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

  void _openBook(int bookId, BookListItem book) {
    if (book.type == BookType.comic) {
      final series = Uri.encodeComponent(book.seriesTitle ?? book.title);
      context.push('/book/$bookId?type=Comic&seriesTitle=$series');
      return;
    }
    context.push('/book/$bookId?type=Novel');
  }

  /// 当前层文件夹的直接子条目，按 index 排序，供封面预览与计数用。
  Map<String, List<ShelfItem>> _directChildren(
    ShelfDraft draft,
    List<ShelfItem> folders,
  ) {
    final buckets = <String, List<ShelfItem>>{
      for (final folder in folders) folder.folderId!: <ShelfItem>[],
    };
    for (final item in draft.items) {
      if (item.parents.length != _parents.length + 1) continue;
      final bucket = buckets[item.parents.last];
      if (bucket == null) continue;
      var matches = true;
      for (var index = 0; index < _parents.length; index += 1) {
        if (item.parents[index] != _parents[index]) {
          matches = false;
          break;
        }
      }
      if (matches) bucket.add(item);
    }
    return buckets.map(
      (id, items) => MapEntry<String, List<ShelfItem>>(id, sortShelfItems(items)),
    );
  }

  Widget _tile({
    required ShelfItem item,
    required int index,
    required ShelfSnapshot snapshot,
    required List<ShelfItem> siblings,
    required Map<String, List<ShelfItem>> children,
    required double tileWidth,
  }) {
    final selected = _selected.contains(item.key);
    final sorting = _mode == _ShelfMode.drag;
    final Widget tile;

    if (item.isBook) {
      final book = snapshot.bookById[item.bookId];
      if (book == null) {
        tile = _UnavailableBookTile(
          selected: selected,
          sorting: sorting,
          onTap: () => _mode == _ShelfMode.select
              ? _toggleSelection(item)
              : _beginSelection(item),
          onLongPress: () => _beginSelection(item),
        );
      } else {
        tile = BookCoverGridItem.fromBook(
          book,
          coverHeight: tileWidth / BookGridLayout.coverAspectRatio,
          selected: selected,
          sorting: sorting,
          onTap: () => _mode == _ShelfMode.select
              ? _toggleSelection(item)
              : _openBook(item.bookId!, book),
          onLongPress: () => _beginSelection(item),
        );
      }
    } else {
      final folderId = item.folderId!;
      final bucket = children[folderId] ?? const <ShelfItem>[];
      final covers = <BookListItem>[];
      for (final child in bucket) {
        if (!child.isBook) continue;
        final book = snapshot.bookById[child.bookId];
        if (book != null) covers.add(book);
        if (covers.length == 4) break;
      }
      final title = item.title.trim();
      tile = ShelfFolderTile(
        title: title.isEmpty ? '未命名文件夹' : title,
        covers: covers,
        childCount: bucket.length,
        selected: selected,
        sorting: sorting,
        onTap: () => _mode == _ShelfMode.select
            ? _toggleSelection(item)
            : _openFolder(folderId),
        onLongPress: () => _beginSelection(item),
      );
    }

    if (_mode != _ShelfMode.drag) return tile;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => _reorder(siblings, details.data, index),
      builder: (context, candidate, _) => LongPressDraggable<int>(
        data: index,
        delay: const Duration(milliseconds: 180),
        feedback: Material(
          type: MaterialType.transparency,
          child: Opacity(
            opacity: 0.9,
            child: SizedBox(width: tileWidth, child: tile),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: candidate.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: tile,
        ),
      ),
    );
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
              style: TextStyle(fontSize: 14, height: 19 / 14, color: colors.onSurface),
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

  Widget _selectionSummary(ShelfDraft draft, List<ShelfItem> siblings) {
    final colors = Theme.of(context).colorScheme;
    final books = shelfSelectionBookCount(draft, _selected);
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
              '已选择 ${_selected.length} 项 · 含 $books 本书',
              style: TextStyle(fontSize: 14, color: colors.onSurface),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll(siblings.map((item) => item.key));
            }),
            child: const Text('全选'),
          ),
          TextButton(
            onPressed: () => _setMode(_ShelfMode.browse),
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
    final snapshot = async.valueOrNull;
    final dirty = snapshot != null && _isDirty(snapshot);
    final draft = snapshot == null ? null : _effectiveDraft(snapshot);
    final title = _parents.isEmpty || draft == null
        ? '书架'
        : _folderTitle(draft, _parents.last);

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
            if (dirty && !_saving)
              TextButton(onPressed: () => _discard(), child: const Text('取消')),
            if (dirty)
              _saving
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
                child: _body(async, snapshot, draft),
              ),
      ),
    );
  }

  Widget _body(
    AsyncValue<ShelfSnapshot?> async,
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              20,
              BookGridLayout.horizontalPadding,
              20,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.columns,
                crossAxisSpacing: BookGridLayout.columnGap,
                mainAxisSpacing: BookGridLayout.rowGap,
                childAspectRatio: layout.tileWidth / layout.skeletonTileHeight,
              ),
              itemCount: layout.skeletonCount(media.height, headerOffset: 120),
              itemBuilder: (_, _) => const BookGridSkeletonTile(),
            ),
          ),
        ],
      );
    }

    final siblings = shelfItemsAtPath(draft, _parents);
    final folders = siblings.where((item) => !item.isBook).toList();
    final children = _directChildren(draft, folders);
    final refreshError = async.hasError ? describeShelfError(async.error!) : null;
    final editorError = _editorError;

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
              if (_parents.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _pathLabel(draft, _parents),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 19 / 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (editorError != null)
                _banner(
                  editorError,
                  onAction: () => setState(() => _editorError = null),
                ),
              if (refreshError != null)
                _banner(
                  '刷新失败：$refreshError',
                  onAction: () => ref.read(shelfProvider.notifier).reload(),
                  actionIcon: Icons.refresh,
                ),
              if (_mode == _ShelfMode.select) _selectionSummary(draft, siblings),
              if (_mode == _ShelfMode.drag)
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
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.columns,
                crossAxisSpacing: BookGridLayout.columnGap,
                mainAxisSpacing: _mode == _ShelfMode.drag ? 18 : BookGridLayout.rowGap,
                childAspectRatio: layout.childAspectRatio,
              ),
              itemCount: siblings.length,
              itemBuilder: (_, index) => _tile(
                item: siblings[index],
                index: index,
                snapshot: snapshot,
                siblings: siblings,
                children: children,
                tileWidth: layout.tileWidth,
              ),
            ),
          ),
      ],
    );
  }
}

/// 快照里缺失详情的书籍占位卡片，仅支持被选中后移出书架。
class _UnavailableBookTile extends StatelessWidget {
  const _UnavailableBookTile({
    required this.selected,
    required this.sorting,
    required this.onTap,
    required this.onLongPress,
  });

  final bool selected;
  final bool sorting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: BookGridLayout.coverAspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant, width: 0.5),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Center(
                    child: Icon(
                      Icons.menu_book_outlined,
                      size: 32,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (selected)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const ColoredBox(
                        color: Color(0xB8D9475D),
                        child: Center(
                          child: Icon(Icons.check, size: 34, color: Colors.white),
                        ),
                      ),
                    ),
                  if (sorting && !selected)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const ColoredBox(
                        color: Color(0x7A000000),
                        child: Center(
                          child: Icon(
                            Icons.drag_indicator,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: BookGridLayout.titleBoxHeight,
            child: Center(
              child: Text(
                '书籍不可用',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 16 / 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
