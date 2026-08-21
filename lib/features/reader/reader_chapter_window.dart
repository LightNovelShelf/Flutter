import 'package:flutter/foundation.dart';

import 'reader_chapter_prerenderer.dart';

/// 阅读器的章节窗口：当前章与前后各一章，都是已经预渲染好、可以直接排版的成品。
///
/// 跨章翻页只是把窗口挪一格——刚离开的那一章留在对面继续当相邻章（往回翻依然无缝），
/// 另一侧腾空，等预渲染把新露出来的那一章补上。窗口之外的章节一律不留。
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

  /// 挪到窗口里的另一章；目标不在窗口里时原样返回。
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

  /// 备好的相邻章接进窗口；不挨着当前章的直接丢掉。
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

  /// 只留当前章：关掉预渲染时用。
  ReaderChapterWindow get alone => current == null
      ? const ReaderChapterWindow.empty()
      : ReaderChapterWindow.only(current!);

  /// 当前章两侧该预渲染的章号；[totalChapters] 为 0 表示还不知道总数。
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
