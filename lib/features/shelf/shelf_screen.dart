import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:romanize/romanize.dart';

import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/book_grid_slivers.dart';
import '../../shared/widgets/state_views.dart';
import '../discover/widgets/novel_series_tile.dart';
import 'shelf_editor_controller.dart';
import 'shelf_series_books_screen.dart';
import 'widgets/shelf_manage_sheet.dart';
import 'widgets/shelf_tile.dart';

enum ShelfSortMode {
  manual,
  titleAscending,
  titleDescending,
  updatedNewest,
  updatedOldest,
  addedNewest,
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
  bool _seriesView = false;
  ShelfSortMode _sort = ShelfSortMode.manual;
  bool _romanizerReady = false;
  bool _romanizerLoading = false;
  final Map<String, String> _sortKeyCache = <String, String>{};

  void _setSort(ShelfSortMode value) {
    setState(() {
      _sort = value;
      _sortKeyCache.clear();
    });
    final needsRomanizer =
        value == ShelfSortMode.titleAscending ||
        value == ShelfSortMode.titleDescending;
    if (!needsRomanizer || _romanizerReady || _romanizerLoading) return;
    _romanizerLoading = true;
    unawaited(
      TextRomanizer.ensureInitialized().then((_) {
        if (!mounted) return;
        setState(() {
          _romanizerReady = true;
          _romanizerLoading = false;
          _sortKeyCache.clear();
        });
      }),
    );
  }

  List<String> get _parents => widget.parents;

  String get _editorKey => shelfEditorKey(_parents);

  ShelfEditorController get _editor =>
      ref.read(shelfEditorProvider(_editorKey).notifier);

  ShelfEditorState get _state => ref.read(shelfEditorProvider(_editorKey));

  String _titleSortKey(String title) => _sortKeyCache.putIfAbsent(title, () {
    final normalized = title.trim().toLowerCase();
    if (!_romanizerReady || normalized.isEmpty) return normalized;
    return TextRomanizer.romanize(normalized).toLowerCase();
  });

  String _itemTitle(ShelfItem item, ShelfLevel level) =>
      item.isBook ? level.bookById[item.bookId]?.title ?? '' : item.title;

  DateTime _addedAt(ShelfItem item) =>
      DateTime.tryParse(item.updatedAt) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _updatedAt(ShelfItem item, ShelfLevel level) => item.isBook
      ? level.bookById[item.bookId]?.lastUpdatedAt ?? _addedAt(item)
      : _addedAt(item);

  int _compareShelfItems(ShelfItem left, ShelfItem right, ShelfLevel level) {
    if (left.isBook != right.isBook) return left.isBook ? 1 : -1;
    final titleOrder = _titleSortKey(_itemTitle(left, level))
        .compareTo(_titleSortKey(_itemTitle(right, level)));
    final order = switch (_sort) {
      ShelfSortMode.manual => left.index.compareTo(right.index),
      ShelfSortMode.titleAscending => titleOrder,
      ShelfSortMode.titleDescending => -titleOrder,
      ShelfSortMode.updatedNewest => _updatedAt(
        right,
        level,
      ).compareTo(_updatedAt(left, level)),
      ShelfSortMode.updatedOldest => _updatedAt(
        left,
        level,
      ).compareTo(_updatedAt(right, level)),
      ShelfSortMode.addedNewest => _addedAt(right).compareTo(_addedAt(left)),
    };
    return order != 0 ? order : titleOrder;
  }

  List<ShelfItem> _sortedSiblings(ShelfLevel level) {
    if (_sort == ShelfSortMode.manual) return level.siblings;
    return List<ShelfItem>.of(level.siblings)
      ..sort((left, right) => _compareShelfItems(left, right, level));
  }

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

  /// 选择移动目标；返回空列表代表根文件夹，返回 null 代表取消。
  Future<List<String>?> _pickDestination(ShelfDraft draft) {
    final editor = _editor;
    final destinations = <(String label, List<String> path)>[
      if (_parents.isNotEmpty) ('根文件夹', const <String>[]),
      for (final folder in shelfFolderPaths(draft))
        if (!editor.isCurrentPath(folder.path))
          (editor.pathLabel(draft, folder.path), folder.path),
    ];
    if (destinations.isEmpty) {
      editor.reportError('还没有可用的目标文件夹，请先新建一个。');
      return Future<List<String>?>.value();
    }
    return showAppChoice<List<String>>(
      context: context,
      title: '移动到文件夹',
      options: destinations,
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
        if (books.isNotEmpty && folders.isEmpty) ShelfManageCommand.moveBooks,
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
    final name = await showAppTextPrompt(
      context: context,
      title: '新建文件夹',
      hint: '请输入文件夹名称',
    );
    if (name == null || !mounted) return;
    _editor.createFolder(name);
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
      message: '将删除所选的 ${folders.length} 个文件夹，其中的书籍会移回书架根目录。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    editor.deleteFolders(folders);
  }

  Future<void> _moveBooks() async {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null) return;
    final editor = _editor;
    final draft = editor.effectiveDraft(snapshot);
    final books = editor.selectedBooks(draft);
    if (books.isEmpty) return;
    final destination = await _pickDestination(draft);
    if (destination == null || !mounted) return;
    editor.moveBooks(
      bookIds: books.map((item) => item.bookId!).toList(),
      destination: destination,
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
          ? '所选文件夹会被删除，其中的书籍将移回书架根目录。'
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
    if (book.type == BookType.comic) {
      final series = Uri.encodeComponent(book.seriesTitle ?? book.title);
      context.push('/book/${book.id}?type=Comic&seriesTitle=$series');
      return;
    }
    context.push('/book/${book.id}?type=Novel');
  }

  void _openShelfSeries(String name, List<BookListItem> books) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShelfSeriesBooksScreen(
          seriesName: name,
          books: books,
          onOpen: (pageContext, book) {
            Navigator.of(pageContext).pop();
            _openBook(book);
          },
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
            if (snapshot != null && editor.mode == ShelfMode.browse)
              _ShelfSortMenu(value: _sort, onChanged: _setSort),
            if (snapshot != null && editor.mode == ShelfMode.browse)
              IconButton(
                tooltip: _seriesView ? '按单本显示' : '按系列显示',
                onPressed: () => setState(() => _seriesView = !_seriesView),
                icon: Icon(
                  _seriesView
                      ? Icons.grid_view_outlined
                      : Icons.folder_copy_outlined,
                ),
              ),
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

    final level = _editor.level(snapshot, draft);
    final siblings = editor.mode == ShelfMode.browse
        ? _sortedSiblings(level)
        : level.siblings;
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
              if (_parents.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _editor.pathLabel(draft, _parents),
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
        else if (_seriesView && editor.mode == ShelfMode.browse)
          _seriesGrid(level, layout, siblings)
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
                items: siblings,
                revision: (level, layout.tileWidth),
                itemBuilder: (_, item, index) => ShelfTile(
                  editorKey: _editorKey,
                  item: item,
                  index: index,
                  siblings: siblings,
                  book: item.isBook ? level.bookById[item.bookId] : null,
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

  Widget _seriesGrid(
    ShelfLevel level,
    BookGridLayout layout,
    List<ShelfItem> siblings,
  ) {
    final grouped = <String, List<BookListItem>>{};
    final entries = <Object>[];
    for (final item in siblings) {
      if (!item.isBook) {
        entries.add(item);
        continue;
      }
      final book = level.bookById[item.bookId];
      final name = book?.type == BookType.novel
          ? book?.seriesTitle?.trim()
          : null;
      if (book == null || name == null || name.isEmpty) {
        entries.add(item);
        continue;
      }
      final books = grouped.putIfAbsent(name, () {
        entries.add(name);
        return <BookListItem>[];
      });
      books.add(book);
    }

    if (_sort != ShelfSortMode.manual) {
      String titleOf(Object entry) =>
          entry is String ? entry : _itemTitle(entry as ShelfItem, level);
      DateTime addedAt(Object entry) => entry is String
          ? grouped[entry]!
                .map(
                  (book) => siblings.firstWhere(
                    (item) => item.isBook && item.bookId == book.id,
                  ),
                )
                .map(_addedAt)
                .reduce((left, right) => left.isAfter(right) ? left : right)
          : _addedAt(entry as ShelfItem);
      DateTime updatedAt(Object entry) => entry is String
          ? grouped[entry]!
                .map((book) => book.lastUpdatedAt)
                .reduce((left, right) => left.isAfter(right) ? left : right)
          : _updatedAt(entry as ShelfItem, level);
      entries.sort((left, right) {
        final leftFolder = left is ShelfItem && !left.isBook;
        final rightFolder = right is ShelfItem && !right.isBook;
        if (leftFolder != rightFolder) return leftFolder ? -1 : 1;
        final titleOrder = _titleSortKey(titleOf(left))
            .compareTo(_titleSortKey(titleOf(right)));
        final order = switch (_sort) {
          ShelfSortMode.manual => 0,
          ShelfSortMode.titleAscending => titleOrder,
          ShelfSortMode.titleDescending => -titleOrder,
          ShelfSortMode.updatedNewest => updatedAt(
            right,
          ).compareTo(updatedAt(left)),
          ShelfSortMode.updatedOldest => updatedAt(
            left,
          ).compareTo(updatedAt(right)),
          ShelfSortMode.addedNewest => addedAt(right).compareTo(addedAt(left)),
        };
        return order != 0 ? order : titleOrder;
      });
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        BookGridLayout.horizontalPadding,
        0,
        BookGridLayout.horizontalPadding,
        32,
      ),
      sliver: SliverGrid(
        gridDelegate: layout.tileGridDelegate(),
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = entries[index];
          if (entry is String) {
            final books = grouped[entry]!;
            final latest = books.reduce(
              (left, right) => left.lastUpdatedAt.isAfter(right.lastUpdatedAt)
                  ? left
                  : right,
            );
            return NovelSeriesTile(
              series: NovelSeriesListItem(
                name: entry,
                coverUrl: latest.coverUrl,
                coverPlaceholder: latest.coverPlaceholder,
                bookCount: books.length,
                lastUpdatedAt: latest.lastUpdatedAt,
              ),
              coverHeight: layout.coverHeight,
              onTap: () => _openShelfSeries(entry, books),
            );
          }
          final item = entry as ShelfItem;
          return ShelfTile(
            editorKey: _editorKey,
            item: item,
            index: level.siblings.indexOf(item),
            siblings: level.siblings,
            book: item.isBook ? level.bookById[item.bookId] : null,
            folder: item.isBook ? null : level.folderPreviews[item.folderId],
            tileWidth: layout.tileWidth,
            onOpenBook: _openBook,
            onOpenFolder: _openFolder,
          );
        }, childCount: entries.length),
      ),
    );
  }
}

class _ShelfSortMenu extends StatelessWidget {
  const _ShelfSortMenu({required this.value, required this.onChanged});

  final ShelfSortMode value;
  final ValueChanged<ShelfSortMode> onChanged;

  static const Map<ShelfSortMode, String> _labels = <ShelfSortMode, String>{
    ShelfSortMode.manual: '手动顺序',
    ShelfSortMode.titleAscending: '标题 A–Z（拼音/罗马字）',
    ShelfSortMode.titleDescending: '标题 Z–A（拼音/罗马字）',
    ShelfSortMode.updatedNewest: '最近更新',
    ShelfSortMode.updatedOldest: '最早更新',
    ShelfSortMode.addedNewest: '最近加入',
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<ShelfSortMode>(
    tooltip: '书架排序',
    icon: const Icon(Icons.sort),
    position: PopupMenuPosition.under,
    onSelected: onChanged,
    itemBuilder: (_) => <PopupMenuEntry<ShelfSortMode>>[
      for (final entry in _labels.entries)
        PopupMenuItem<ShelfSortMode>(
          value: entry.key,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value),
            trailing: entry.key == value ? const Icon(Icons.check) : null,
          ),
        ),
    ],
  );
}
