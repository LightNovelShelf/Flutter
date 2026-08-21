import 'package:flutter/foundation.dart';

import 'reader_chapter_prerenderer.dart';

/// 章节窗口：当前章与前后各一章，均已预渲染。
///
/// 跨章翻页把窗口平移一格，窗口外的章节不保留。
@immutable
class ReaderChapterWindow {
  const ReaderChapterWindow({this.previous, this.current, this.next});

  const ReaderChapterWindow.empty()
    : previous = null,
      current = null,
      next = null;

  const ReaderChapterWindow.only(ReaderPreparedChapter chapter)
    : previous = null,
      current = chapter,
      next = null;

  final ReaderPreparedChapter? previous;
  final ReaderPreparedChapter? current;
  final ReaderPreparedChapter? next;

  bool get isEmpty => current == null;

  /// 窗口里的这一章，没有则返回 null。
  ReaderPreparedChapter? at(int sortNum) {
    for (final chapter in <ReaderPreparedChapter?>[previous, current, next]) {
      if (chapter != null && chapter.sortNum == sortNum) return chapter;
    }
    return null;
  }

  /// 移到窗口里的另一章；目标不在窗口里时原样返回。
  ReaderChapterWindow moveTo(int sortNum) {
    final target = at(sortNum);
    final leaving = current;
    if (target == null || leaving == null || identical(target, leaving)) {
      return this;
    }
    return sortNum > leaving.sortNum
        ? ReaderChapterWindow(previous: leaving, current: target)
        : ReaderChapterWindow(current: target, next: leaving);
  }

  /// 把预渲染好的相邻章接进窗口，不与当前章相邻的丢弃。
  ReaderChapterWindow withNeighbor(ReaderPreparedChapter chapter) {
    final offset = current == null ? 0 : chapter.sortNum - current!.sortNum;
    return switch (offset) {
      1 => ReaderChapterWindow(
        previous: previous,
        current: current,
        next: chapter,
      ),
      -1 => ReaderChapterWindow(
        previous: chapter,
        current: current,
        next: next,
      ),
      _ => this,
    };
  }

  /// 只保留当前章，关闭预渲染时用。
  ReaderChapterWindow get alone => current == null
      ? const ReaderChapterWindow.empty()
      : ReaderChapterWindow.only(current!);

  /// 当前章两侧待预渲染的章号；[totalChapters] 为 0 表示总数未知。
  List<int> neighborSortNums(int totalChapters) {
    final sortNum = current?.sortNum;
    if (sortNum == null) return const <int>[];
    return <int>[
      if (sortNum > 1) sortNum - 1,
      if (totalChapters == 0 || sortNum < totalChapters) sortNum + 1,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderChapterWindow &&
      identical(other.previous, previous) &&
      identical(other.current, current) &&
      identical(other.next, next);

  @override
  int get hashCode => Object.hash(previous, current, next);
}
