import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/models.dart';
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
    required this.id,
    required this.sortNum,
    required this.title,
    this.subtitle,
  });

  final int id;
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
}) =>
    showModalBottomSheet<ReaderChapterSelection>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 1,
        snap: true,
        snapSizes: const <double>[0.6, 1],
        builder: (context, controller) => _ReaderChapterSheet(
          bookId: bookId,
          currentSortNum: currentSortNum,
          comic: comic,
          scrollController: controller,
        ),
      ),
    );

class _ReaderChapterSheet extends ConsumerStatefulWidget {
  const _ReaderChapterSheet({
    required this.bookId,
    required this.currentSortNum,
    required this.comic,
    required this.scrollController,
  });

  final int bookId;
  final int currentSortNum;
  final bool comic;
  final ScrollController scrollController;

  @override
  ConsumerState<_ReaderChapterSheet> createState() =>
      _ReaderChapterSheetState();
}

class _ReaderChapterSheetState extends ConsumerState<_ReaderChapterSheet> {
  static const double _rowHeight = 58;
  bool _scrolled = false;

  /// 打开目录时直接定位到当前章节，长目录不必手动翻找。
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
    final restore = entry.sortNum == widget.currentSortNum ||
        entry.id == readPosition?.chapterId;
    Navigator.of(context).pop(
      ReaderChapterSelection(
        sortNum: entry.sortNum,
        openPosition:
            restore ? ReaderOpenPosition.saved : ReaderOpenPosition.start,
      ),
    );
  }

  Widget _list(List<_ChapterEntry> entries, BookReadPosition? readPosition) {
    final colors = Theme.of(context).colorScheme;
    final currentIndex =
        entries.indexWhere((entry) => entry.sortNum == widget.currentSortNum);
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
      itemBuilder: (context, index) {
        final entry = entries[index];
        final current = index == currentIndex;
        return InkWell(
          onTap: () => _select(entry, readPosition),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: _rowHeight,
            decoration: BoxDecoration(
              color: current ? colors.primaryContainer : null,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: current ? colors.primary : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: current
                      ? Icon(Icons.check, size: 17, color: colors.onPrimary)
                      : Text(
                          '${entry.sortNum}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
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
                          fontWeight:
                              current ? FontWeight.w700 : FontWeight.w600,
                          color: current
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                        ),
                      ),
                      if (entry.subtitle != null)
                        Text(
                          entry.subtitle!,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final AsyncValue<Object> source = widget.comic
        ? ref.watch(readerComicInfoProvider(widget.bookId))
        : ref.watch(readerBookDetailProvider(widget.bookId));
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.list_alt, size: 22, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                '目录',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: source.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorStateView(
              message: '$error',
              onRetry: () {
                if (widget.comic) {
                  ref.invalidate(readerComicInfoProvider(widget.bookId));
                } else {
                  ref.invalidate(readerBookDetailProvider(widget.bookId));
                }
              },
            ),
            data: (Object data) {
              if (data is ComicInfo) {
                return _list(
                  <_ChapterEntry>[
                    for (final chapter in data.chapters)
                      _ChapterEntry(
                        id: chapter.id,
                        sortNum: chapter.sortNum,
                        title: chapter.title,
                        subtitle: '共 ${chapter.pageCount} 页',
                      ),
                  ],
                  data.readPosition,
                );
              }
              final detail = data as BookDetail;
              return _list(
                <_ChapterEntry>[
                  for (var index = 0; index < detail.chapters.length; index++)
                    _ChapterEntry(
                      id: detail.chapters[index].id,
                      sortNum: index + 1,
                      title: detail.chapters[index].title,
                    ),
                ],
                detail.readPosition,
              );
            },
          ),
        ),
      ],
    );
  }
}
