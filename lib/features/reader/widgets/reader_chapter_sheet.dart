import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/state_views.dart';
import '../reader_open_position.dart';
import '../reader_providers.dart';

class ReaderChapterSelection {
  const ReaderChapterSelection({
    required this.sortNum,
    required this.openPosition,
  });

  final int sortNum;
  final ReaderOpenPosition openPosition;
}

class _ChapterEntry {
  const _ChapterEntry({
    this.id,
    required this.sortNum,
    required this.title,
    this.subtitle,
  });

  final int? id;
  final int sortNum;
  final String title;
  final String? subtitle;
}

/// 目录弹层：选中当前章或进度所在章恢复进度，其余章节从头开始。
Future<ReaderChapterSelection?> showReaderChapterSheet(
  BuildContext context, {
  required int bookId,
  required int currentSortNum,
  required bool comic,
  List<String>? novelChapterTitles,
}) {
  assert(comic || novelChapterTitles != null);
  return showDraggableSheet<ReaderChapterSelection>(
    context,
    builder: (context, controller) => _ReaderChapterSheet(
      bookId: bookId,
      currentSortNum: currentSortNum,
      comic: comic,
      novelChapterTitles: novelChapterTitles,
      scrollController: controller,
    ),
  );
}

class _ReaderChapterSheet extends ConsumerStatefulWidget {
  const _ReaderChapterSheet({
    required this.bookId,
    required this.currentSortNum,
    required this.comic,
    required this.novelChapterTitles,
    required this.scrollController,
  });

  final int bookId;
  final int currentSortNum;
  final bool comic;
  final List<String>? novelChapterTitles;
  final ScrollController scrollController;

  @override
  ConsumerState<_ReaderChapterSheet> createState() =>
      _ReaderChapterSheetState();
}

const double _rowHeight = 58;

class _ReaderChapterSheetState extends ConsumerState<_ReaderChapterSheet> {
  bool _scrolled = false;

  /// 打开目录时滚动到当前章节。
  void _revealCurrent(int index) {
    if (_scrolled || index < 0) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final target = ((index - 2) * _rowHeight).clamp(
        0.0,
        widget.scrollController.position.maxScrollExtent,
      );
      widget.scrollController.jumpTo(target);
    });
  }

  void _select(_ChapterEntry entry, BookReadPosition? readPosition) {
    final restore =
        entry.sortNum == widget.currentSortNum ||
        (entry.id != null && entry.id == readPosition?.chapterId);
    Navigator.of(context).pop(
      ReaderChapterSelection(
        sortNum: entry.sortNum,
        openPosition: restore
            ? ReaderOpenPosition.saved
            : ReaderOpenPosition.start,
      ),
    );
  }

  Widget _list(List<_ChapterEntry> entries, BookReadPosition? readPosition) {
    final colors = Theme.of(context).colorScheme;
    final currentIndex = entries.indexWhere(
      (entry) => entry.sortNum == widget.currentSortNum,
    );
    _revealCurrent(currentIndex);
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 0.5,
        indent: 58,
        endIndent: 12,
        color: colors.outlineVariant,
      ),
      itemBuilder: (context, index) => _ChapterTile(
        entry: entries[index],
        current: index == currentIndex,
        onTap: () => _select(entries[index], readPosition),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final novelEntries = <_ChapterEntry>[
      for (
        var index = 0;
        index < (widget.novelChapterTitles?.length ?? 0);
        index++
      )
        _ChapterEntry(
          sortNum: index + 1,
          title: widget.novelChapterTitles![index],
        ),
    ];
    return Column(
      children: <Widget>[
        const SheetHeader(icon: Icons.list_alt, title: '目录'),
        Expanded(
          child: widget.comic
              ? ref
                    .watch(readerBookDetailProvider(widget.bookId))
                    .when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => ErrorStateView(
                        message: '$error',
                        onRetry: () => ref.invalidate(
                          readerBookDetailProvider(widget.bookId),
                        ),
                      ),
                      data: (data) => _list(<_ChapterEntry>[
                        for (final chapter in data.chapters)
                          _ChapterEntry(
                            id: chapter.id,
                            sortNum: chapter.sortNum,
                            title: chapter.title,
                            subtitle: '共 ${chapter.pageCount} 页',
                          ),
                      ], data.readPosition),
                    )
              : _list(novelEntries, null),
        ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.entry,
    required this.current,
    required this.onTap,
  });

  final _ChapterEntry entry;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final subtitle = entry.subtitle;
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Text(
                      '${entry.sortNum}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: current
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: current ? colors.primary : colors.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
