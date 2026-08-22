import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_cover_grid_item.dart';
import '../shelf_editor_controller.dart';
import 'shelf_folder_tile.dart';
import 'unavailable_book_tile.dart';

/// 书架卡片：只订阅自身选中态与拖拽模式，一次选中不再重建整屏卡片。
class ShelfTile extends ConsumerWidget {
  const ShelfTile({
    super.key,
    required this.editorKey,
    required this.item,
    required this.index,
    required this.siblings,
    required this.book,
    required this.folder,
    required this.tileWidth,
    required this.onOpenBook,
    required this.onOpenFolder,
  });

  final String editorKey;
  final ShelfItem item;
  final int index;
  final List<ShelfItem> siblings;

  /// 书籍条目对应的书籍，已下架时为空。
  final BookListItem? book;

  /// 文件夹条目的封面预览，书籍条目为空。
  final ShelfFolderPreview? folder;
  final double tileWidth;
  final void Function(BookListItem book) onOpenBook;
  final void Function(String folderId) onOpenFolder;

  /// 选择模式下点击是切换选中；`open` 为空表示条目已下架，只能被选中。
  void _handleTap(WidgetRef ref, VoidCallback? open) {
    final provider = shelfEditorProvider(editorKey);
    final editor = ref.read(provider.notifier);
    if (ref.read(provider).mode == ShelfMode.select) {
      editor.toggleSelection(item);
      return;
    }
    if (open == null) {
      editor.beginSelection(item);
      return;
    }
    open();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = shelfEditorProvider(editorKey);
    final selected = ref.watch(
      provider.select((state) => state.selected.contains(item.key)),
    );
    final sorting = ref.watch(
      provider.select((state) => state.mode == ShelfMode.drag),
    );
    void beginSelection() => ref.read(provider.notifier).beginSelection(item);

    final Widget tile;
    if (item.isBook) {
      final resolved = book;
      if (resolved == null) {
        tile = UnavailableBookTile(
          selected: selected,
          sorting: sorting,
          onTap: () => _handleTap(ref, null),
          onLongPress: beginSelection,
        );
      } else {
        tile = BookCoverGridItem.fromBook(
          resolved,
          coverHeight: tileWidth / BookGridLayout.coverAspectRatio,
          selected: selected,
          sorting: sorting,
          onTap: () => _handleTap(ref, () => onOpenBook(resolved)),
          onLongPress: beginSelection,
        );
      }
    } else {
      final preview = folder ?? ShelfFolderPreview.empty;
      final folderId = item.folderId!;
      final title = item.title.trim();
      tile = ShelfFolderTile(
        title: title.isEmpty ? '未命名文件夹' : title,
        covers: preview.covers,
        childCount: preview.count,
        selected: selected,
        sorting: sorting,
        onTap: () => _handleTap(ref, () => onOpenFolder(folderId)),
        onLongPress: beginSelection,
      );
    }

    if (!sorting) return tile;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) =>
          ref.read(provider.notifier).reorder(siblings, details.data, index),
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
}
