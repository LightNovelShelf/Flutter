import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../book_providers.dart';

/// 书架按钮与开始/继续阅读按钮。书架状态在 [shelfToggleProvider]。
class BookActionRow extends ConsumerWidget {
  const BookActionRow({
    super.key,
    required this.bookId,
    required this.bundle,
    required this.currentIndex,
    required this.onRead,
  });

  final int bookId;
  final BookDetailBundle bundle;

  /// 当前阅读到的章节下标，`-1` 表示未读。
  final int currentIndex;
  final void Function(int sortNum) onRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final detail = bundle.detail;
    final hasChapters = detail.chapters.isNotEmpty;
    final shelf = ref.watch(shelfToggleProvider(bookId));
    final resolvedInShelf =
        shelf.inShelf ?? ref.watch(bookInShelfProvider(bookId)).value ?? false;
    final continueTitle = currentIndex >= 0
        ? cleanChapterTitle(detail.chapters[currentIndex].title)
        : null;
    final label = continueTitle == null
        ? '开始阅读'
        : '继续 · ${continueTitle.length > 15 ? '${continueTitle.substring(0, 15)}…' : continueTitle}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // 漫画按系列聚合，没有单卷书架条目。
            if (!bundle.isComic) ...<Widget>[
              SizedBox(
                width: 56,
                height: 56,
                child: Material(
                  color: resolvedInShelf
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: shelf.busy
                        ? null
                        : () => ref
                              .read(shelfToggleProvider(bookId).notifier)
                              .toggle(resolvedInShelf),
                    child: Center(
                      child: shelf.busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : Icon(
                              resolvedInShelf
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              size: 25,
                              color: resolvedInShelf
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: hasChapters
                      ? () => onRead(currentIndex >= 0 ? currentIndex + 1 : 1)
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (shelf.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              shelf.error!,
              style: TextStyle(fontSize: 13, height: 1.38, color: colors.error),
            ),
          ),
      ],
    );
  }
}
