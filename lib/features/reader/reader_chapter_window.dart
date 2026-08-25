import 'package:flutter/foundation.dart';

import 'reader_chapter_prerenderer.dart';

/// 章节窗口：当前章与两侧已备好的连续章节，按章号升序。
///
/// 翻页条按窗口里的章节接页，一屏可能跨两章，所以窗口不止当前章与前后各一章：
/// 章节太短时右栏会再往后接一章。离当前章超过 [retainAround] 半径的章移出窗口，
/// 正文块与几何随之释放；章节内容仍留在预渲染缓存里，回头再看不会重新请求。
@immutable
class ReaderChapterWindow {
  const ReaderChapterWindow._(this.chapters, this.currentIndex);

  const ReaderChapterWindow.empty()
    : chapters = const <ReaderPreparedChapter>[],
      currentIndex = -1;

  ReaderChapterWindow.only(ReaderPreparedChapter chapter)
    : chapters = <ReaderPreparedChapter>[chapter],
      currentIndex = 0;

  /// 章号连续且升序。
  final List<ReaderPreparedChapter> chapters;

  /// [chapters] 里当前章的下标；空窗口为 -1。
  final int currentIndex;

  bool get isEmpty => currentIndex < 0;

  ReaderPreparedChapter? get current => isEmpty ? null : chapters[currentIndex];

  /// 窗口里的这一章，没有则返回 null。
  ReaderPreparedChapter? at(int sortNum) {
    for (final chapter in chapters) {
      if (chapter.sortNum == sortNum) return chapter;
    }
    return null;
  }

  /// 移到窗口里的另一章；目标不在窗口里时原样返回。
  ReaderChapterWindow moveTo(int sortNum) {
    final index = chapters.indexWhere((chapter) => chapter.sortNum == sortNum);
    return index < 0 || index == currentIndex
        ? this
        : ReaderChapterWindow._(chapters, index);
  }

  /// 把备好的一章接在窗口两端；与窗口不相邻的丢弃。
  ReaderChapterWindow withNeighbor(ReaderPreparedChapter chapter) {
    if (isEmpty || at(chapter.sortNum) != null) return this;
    if (chapter.sortNum == chapters.first.sortNum - 1) {
      return ReaderChapterWindow._(<ReaderPreparedChapter>[
        chapter,
        ...chapters,
      ], currentIndex + 1);
    }
    if (chapter.sortNum == chapters.last.sortNum + 1) {
      return ReaderChapterWindow._(<ReaderPreparedChapter>[
        ...chapters,
        chapter,
      ], currentIndex);
    }
    return this;
  }

  /// 只留当前章两侧各 [radius] 章。
  ReaderChapterWindow retainAround(int radius) {
    final anchor = current;
    if (anchor == null) return this;
    final kept = <ReaderPreparedChapter>[
      for (final chapter in chapters)
        if ((chapter.sortNum - anchor.sortNum).abs() <= radius) chapter,
    ];
    return kept.length == chapters.length
        ? this
        : ReaderChapterWindow._(kept, kept.indexOf(anchor));
  }

  @override
  bool operator ==(Object other) {
    if (other is! ReaderChapterWindow) return false;
    if (other.currentIndex != currentIndex ||
        other.chapters.length != chapters.length) {
      return false;
    }
    for (var index = 0; index < chapters.length; index++) {
      if (!identical(other.chapters[index], chapters[index])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(currentIndex, Object.hashAll(chapters));
}
