import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../data/repositories/shelf_books.dart';
import '../../../shared/layout/book_grid_layout.dart';
import '../../../shared/widgets/book_cover_grid_item.dart';
import '../shelf_editor_controller.dart';
import 'shelf_folder_tile.dart';
import 'unavailable_book_tile.dart';

/// 按需订阅书籍信息与自身编辑状态的书架卡片。
class ShelfTile extends ConsumerWidget {
  const ShelfTile({
    super.key,
    required this.editorKey,
    required this.item,
    required this.index,
    required this.siblings,
    required this.folder,
    required this.tileWidth,
    required this.onOpenBook,
    required this.onOpenFolder,
  });

  final String editorKey;
  final ShelfItem item;
  final int index;
  final List<ShelfItem> siblings;

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
      final request = shelfBookProvider(item.bookId!);
      final async = ref.watch(request);
      final resolved = async.value;
      if (async.isLoading) {
        tile = const BookGridSkeletonTile();
      } else if (async.hasError) {
        tile = UnavailableBookTile(
          title: '加载失败，点击重试',
          selected: selected,
          sorting: sorting,
          onTap: () => ref.invalidate(request),
          onLongPress: beginSelection,
        );
      } else if (resolved == null) {
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
      final covers = <BookListItem>[];
      var failed = false;
      for (final id in preview.bookIds) {
        final async = ref.watch(shelfBookProvider(id));
        final book = async.value;
        if (book != null) covers.add(book);
        failed = failed || async.hasError;
      }
      tile = ShelfFolderTile(
        title: title.isEmpty ? '未命名文件夹' : title,
        covers: covers,
        childCount: preview.count,
        selected: selected,
        sorting: sorting,
        onTap: () {
          if (failed) {
            for (final id in preview.bookIds) {
              ref.invalidate(shelfBookProvider(id));
            }
          }
          _handleTap(ref, () => onOpenFolder(folderId));
        },
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
