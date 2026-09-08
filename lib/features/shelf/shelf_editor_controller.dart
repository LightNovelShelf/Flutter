import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../data/api/models.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';

enum ShelfMode { browse, select, drag }

/// 书架页的编辑态：草稿、多选与保存进度。
@immutable
class ShelfEditorState {
  const ShelfEditorState({
    this.draft,
    this.selected = const <String>{},
    this.mode = ShelfMode.browse,
    this.error,
    this.saving = false,
  });

  /// 非空表示正在编辑；为空时以服务端快照为准。
  final ShelfDraft? draft;
  final Set<String> selected;
  final ShelfMode mode;
  final String? error;
  final bool saving;

  ShelfEditorState copyWith({
    ShelfDraft? draft,
    Set<String>? selected,
    ShelfMode? mode,
    String? error,
    bool? saving,
    bool clearError = false,
  }) => ShelfEditorState(
    draft: draft ?? this.draft,
    selected: selected ?? this.selected,
    mode: mode ?? this.mode,
    error: clearError ? null : (error ?? this.error),
    saving: saving ?? this.saving,
  );
}

/// 文件夹卡片的前 4 本直接子书籍 ID 与直接条目数。
@immutable
class ShelfFolderPreview {
  const ShelfFolderPreview({required this.bookIds, required this.count});

  static const ShelfFolderPreview empty = ShelfFolderPreview(
    bookIds: <int>[],
    count: 0,
  );

  final List<int> bookIds;
  final int count;
}

/// 渲染当前层需要的全部派生数据，由 [ShelfEditorController.level] 记忆化。
@immutable
class ShelfLevel {
  const ShelfLevel({required this.siblings, required this.folderPreviews});

  final List<ShelfItem> siblings;
  final Map<String, ShelfFolderPreview> folderPreviews;
}

/// family 键必须值相等，而 `List<String>` 是引用相等（路由每次重建都给新列表），
/// 所以按编码后的路径分桶。
String shelfEditorKey(List<String> parents) => jsonEncode(parents);

/// 书架编辑状态机，草稿的增删改都在这里完成。
class ShelfEditorController extends Notifier<ShelfEditorState> {
  ShelfEditorController(this.arg);

  /// [shelfEditorKey] 编码后的当前文件夹路径。
  final String arg;

  late final List<String> parents = (jsonDecode(arg) as List<Object?>)
      .cast<String>();

  bool _disposed = false;

  @override
  ShelfEditorState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const ShelfEditorState();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  ShelfSnapshot? _draftSource;
  ShelfDraft? _snapshotDraft;

  /// `toDraft` 会深拷全部条目，按快照引用缓存，编辑态抖动时不再每帧重建草稿。
  ShelfDraft effectiveDraft(ShelfSnapshot snapshot) {
    final draft = state.draft;
    if (draft != null) return draft;
    final cached = _snapshotDraft;
    if (cached != null && identical(_draftSource, snapshot)) return cached;
    final derived = snapshot.toDraft();
    _draftSource = snapshot;
    _snapshotDraft = derived;
    return derived;
  }

  bool isDirty(ShelfSnapshot snapshot) {
    final draft = state.draft;
    return draft != null && shelfDraftHasChanges(snapshot, draft);
  }

  ShelfItem? _findFolder(ShelfDraft draft, String id) {
    for (final item in draft.items) {
      if (!item.isBook && item.folderId == id) return item;
    }
    return null;
  }

  String folderTitle(ShelfDraft draft, String id) {
    final folder = _findFolder(draft, id);
    if (folder == null) return '文件夹已不存在';
    final title = folder.title.trim();
    return title.isEmpty ? '未命名文件夹' : title;
  }

  String pathLabel(ShelfDraft draft, List<String> path) => path.isEmpty
      ? '根文件夹'
      : path.map((id) => folderTitle(draft, id)).join(' / ');

  List<ShelfItem> selectedFolders(ShelfDraft draft) => draft.items
      .where((item) => !item.isBook && state.selected.contains(item.key))
      .toList();

  List<ShelfItem> selectedBooks(ShelfDraft draft) => draft.items
      .where((item) => item.isBook && state.selected.contains(item.key))
      .toList();

  bool isCurrentPath(List<String> path) {
    if (path.length != parents.length) return false;
    for (var index = 0; index < path.length; index += 1) {
      if (path[index] != parents[index]) return false;
    }
    return true;
  }

  ShelfDraft? _levelDraft;
  ShelfLevel? _level;

  /// 按草稿引用缓存当前层的派生数据。
  ShelfLevel level(ShelfDraft draft) {
    final cached = _level;
    if (cached != null && identical(_levelDraft, draft)) {
      return cached;
    }
    final computed = _computeLevel(draft);
    _levelDraft = draft;
    _level = computed;
    return computed;
  }

  ShelfLevel _computeLevel(ShelfDraft draft) {
    final siblings = shelfItemsAtPath(draft, parents);
    final buckets = <String, List<ShelfItem>>{};
    for (final item in siblings) {
      if (!item.isBook) buckets[item.folderId!] = <ShelfItem>[];
    }
    for (final item in draft.items) {
      if (item.parents.length != parents.length + 1) continue;
      final bucket = buckets[item.parents.last];
      if (bucket == null) continue;
      var matches = true;
      for (var index = 0; index < parents.length; index += 1) {
        if (item.parents[index] != parents[index]) {
          matches = false;
          break;
        }
      }
      if (matches) bucket.add(item);
    }
    final previews = <String, ShelfFolderPreview>{};
    for (final entry in buckets.entries) {
      final bookIds = <int>[];
      for (final child in sortShelfItems(entry.value)) {
        if (!child.isBook) continue;
        bookIds.add(child.bookId!);
        if (bookIds.length == 4) break;
      }
      previews[entry.key] = ShelfFolderPreview(
        bookIds: bookIds,
        count: entry.value.length,
      );
    }
    return ShelfLevel(siblings: siblings, folderPreviews: previews);
  }

  /// 变更写入草稿，校验失败时只记录错误，草稿保持不变。
  void _applyMutation(ShelfDraft Function(ShelfDraft draft) apply) {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null || state.saving) return;
    try {
      state = state.copyWith(
        draft: apply(effectiveDraft(snapshot)),
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        error: describeShelfError(error, fallback: '书架操作失败。'),
      );
    }
  }

  void reportError(String message) => state = state.copyWith(error: message);

  void clearError() => state = state.copyWith(clearError: true);

  void setMode(ShelfMode mode) => state = state.copyWith(
    mode: mode,
    // 避免选中项跨模式残留。
    selected: mode == ShelfMode.select ? null : const <String>{},
  );

  void toggleSelection(ShelfItem item) {
    final selected = Set<String>.of(state.selected);
    if (!selected.remove(item.key)) selected.add(item.key);
    state = state.copyWith(
      selected: selected,
      mode: selected.isEmpty && state.mode == ShelfMode.select
          ? ShelfMode.browse
          : null,
    );
  }

  void beginSelection(ShelfItem item) => state = state.copyWith(
    mode: ShelfMode.select,
    selected: <String>{item.key},
  );

  void selectAll(List<ShelfItem> siblings) => state = state.copyWith(
    selected: siblings.map((item) => item.key).toSet(),
  );

  void _clearSelection() => state = state.copyWith(selected: const <String>{});

  void reorder(List<ShelfItem> siblings, int from, int to) {
    if (from == to) return;
    final keys = siblings.map((item) => item.key).toList();
    final moved = keys.removeAt(from);
    keys.insert(to, moved);
    _applyMutation(
      (draft) => reorderShelfSiblings(
        draft,
        parents: parents,
        orderedKeys: keys,
        now: _now(),
      ),
    );
  }

  void createFolder(String name) {
    // 服务端的书架结构中文件夹只有根层级，新建文件夹落在根目录。
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _applyMutation(
      (draft) => createShelfFolder(draft, id: id, title: name, now: _now()),
    );
  }

  void renameFolder(String id, String name) => _applyMutation(
    (draft) => renameShelfFolder(draft, id: id, title: name, now: _now()),
  );

  void deleteFolders(List<ShelfItem> folders) {
    _applyMutation((draft) {
      var next = draft;
      final now = _now();
      for (final folder in folders) {
        next = deleteShelfFolder(next, id: folder.folderId!, now: now);
      }
      return next;
    });
    _clearSelection();
  }

  void moveBooks({
    required List<int> bookIds,
    required List<String> destination,
  }) {
    _applyMutation(
      (draft) => moveShelfBooks(
        draft,
        bookIds: bookIds,
        destination: destination,
        now: _now(),
      ),
    );
    _clearSelection();
  }

  void removeItems(Set<String> keys) {
    _applyMutation((draft) => removeShelfItems(draft, keys: keys, now: _now()));
    _clearSelection();
  }

  /// 保存草稿，返回是否已写回服务端。
  Future<bool> save() async {
    final draft = state.draft;
    if (draft == null || state.saving) return false;
    state = state.copyWith(saving: true, clearError: true);
    try {
      await ref.read(shelfProvider.notifier).save(draft);
      if (_disposed) return true;
      state = const ShelfEditorState();
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        saving: false,
        error: describeShelfError(error, fallback: '保存失败，请稍后重试。'),
      );
      return false;
    }
  }

  void discard() => state = ShelfEditorState(saving: state.saving);
}

final NotifierProviderFamily<ShelfEditorController, ShelfEditorState, String>
shelfEditorProvider =
    NotifierProvider.family<ShelfEditorController, ShelfEditorState, String>(
      ShelfEditorController.new,
      isAutoDispose: true,
    );
