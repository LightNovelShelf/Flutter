import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../data/api/models.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';
import 'shelf_filter.dart';

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

/// 书架编辑状态机：草稿全局一份，层级只决定渲染哪一层。
class ShelfEditorController extends Notifier<ShelfEditorState> {
  bool _disposed = false;

  @override
  ShelfEditorState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const ShelfEditorState();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  List<ShelfItem> selectedFolders(ShelfDraft draft) => draft.items
      .where((item) => !item.isBook && state.selected.contains(item.key))
      .toList();

  List<ShelfItem> selectedBooks(ShelfDraft draft) => draft.items
      .where((item) => item.isBook && state.selected.contains(item.key))
      .toList();

  /// 变更写入草稿，返回是否写入成功；校验失败时只记录错误，草稿保持不变。
  bool _applyMutation(ShelfDraft Function(ShelfDraft draft) apply) {
    final snapshot = ref.read(shelfProvider).value;
    if (snapshot == null || state.saving) return false;
    try {
      state = state.copyWith(
        draft: apply(state.draft ?? snapshot.toDraft()),
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        error: describeShelfError(error, fallback: '书架操作失败。'),
      );
      return false;
    }
  }

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

  /// 重排 [parents] 这一层：[siblings] 是该层当前显示的顺序。
  void reorder(
    List<ShelfItem> siblings,
    int from,
    int to, {
    required List<String> parents,
  }) {
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

  static String _newFolderId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  /// 在 [parents] 这一层新建文件夹。
  void createFolder(String name, {required List<String> parents}) {
    final id = _newFolderId();
    _applyMutation(
      (draft) => createShelfFolder(
        draft,
        id: id,
        title: name,
        parents: parents,
        now: _now(),
      ),
    );
  }

  void renameFolder(String id, String name) => _applyMutation(
    (draft) => renameShelfFolder(draft, id: id, title: name, now: _now()),
  );

  void deleteFolders(List<ShelfItem> folders) {
    final applied = _applyMutation((draft) {
      var next = draft;
      final now = _now();
      for (final folder in folders) {
        next = deleteShelfFolder(next, id: folder.folderId!, now: now);
      }
      return next;
    });
    if (applied) _clearSelection();
  }

  /// 移动选中的条目；[newFolderName] 非空时先在目标路径下建好文件夹再移进去。
  void moveItems({
    required Set<String> keys,
    required List<String> destination,
    String? newFolderName,
  }) {
    final applied = _applyMutation((draft) {
      final now = _now();
      var next = draft;
      var target = destination;
      final name = newFolderName?.trim();
      if (name != null && name.isNotEmpty) {
        final id = _newFolderId();
        next = createShelfFolder(
          next,
          id: id,
          title: name,
          parents: destination,
          now: now,
        );
        target = <String>[...destination, id];
      }
      return moveShelfItems(next, keys: keys, destination: target, now: now);
    });
    if (applied) _clearSelection();
  }

  void removeItems(Set<String> keys) {
    final applied = _applyMutation(
      (draft) => removeShelfItems(draft, keys: keys),
    );
    if (applied) _clearSelection();
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

/// 草稿全局一份：进出文件夹只是换层渲染，不该各层各存一份。
final NotifierProvider<ShelfEditorController, ShelfEditorState>
shelfEditorProvider = NotifierProvider<ShelfEditorController, ShelfEditorState>(
  ShelfEditorController.new,
);

/// 当前生效的草稿：编辑中用草稿本身，否则用快照的深拷贝。
///
/// `toDraft` 会深拷全部条目，挂在 provider 上，快照与草稿都没换时不重建。
final Provider<ShelfDraft?> shelfDraftProvider = Provider<ShelfDraft?>((ref) {
  final draft = ref.watch(shelfEditorProvider.select((state) => state.draft));
  if (draft != null) return draft;
  final snapshot = ref.watch(shelfProvider.select((async) => async.value));
  return snapshot?.toDraft();
});

/// 草稿相对服务端快照是否有改动，整个书架共享一个结论。
final Provider<bool> shelfDirtyProvider = Provider<bool>((ref) {
  final draft = ref.watch(shelfEditorProvider.select((state) => state.draft));
  if (draft == null) return false;
  final snapshot = ref.watch(shelfProvider.select((async) => async.value));
  return snapshot != null && shelfDraftHasChanges(snapshot, draft);
});

/// 渲染用的筛选。拖拽排序按可视位置回写 index，隐藏掉条目会算错，所以排序时不筛选。
final Provider<ShelfFilter> shelfLevelFilterProvider = Provider<ShelfFilter>((
  ref,
) {
  final dragging = ref.watch(
    shelfEditorProvider.select((state) => state.mode == ShelfMode.drag),
  );
  if (dragging) return ShelfFilter.all;
  return ref.watch(shelfFilterProvider);
});

/// family 键必须值相等，而 `List<String>` 是引用相等（路由每次重建都给新列表），
/// 所以按编码后的路径分桶。
String shelfLevelKey(List<String> parents) => jsonEncode(parents);

/// 按路径分桶记忆化该层的派生数据：草稿与筛选没变就不重算。
final ProviderFamily<ShelfLevel, String> shelfLevelProvider =
    Provider.family<ShelfLevel, String>((ref, key) {
      final draft = ref.watch(shelfDraftProvider);
      if (draft == null) return ShelfLevel.empty;
      return shelfLevelAt(
        draft,
        (jsonDecode(key) as List<Object?>).cast<String>(),
        type: ref.watch(shelfLevelFilterProvider).bookType,
      );
    }, isAutoDispose: true);
