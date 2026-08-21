import 'dart:math' as math;

import '../../data/api/models.dart';
import '../../data/repositories/read_position_cache.dart';
import 'reader_html_blocks.dart';
import 'reader_open_position.dart';

/// 阅读定位：章节序号换算、续读位置取舍与 locator 查找，两个阅读器共用一套语义。

class ReaderRestorePosition {
  const ReaderRestorePosition({
    required this.chapterId,
    required this.position,
  });

  final int chapterId;
  final String position;
}

/// 本地缓存的进度；`isPending` 表示尚未被服务端确认。
class CachedReaderRestorePosition extends ReaderRestorePosition {
  const CachedReaderRestorePosition({
    required super.chapterId,
    required super.position,
    this.isPending = true,
  });

  final bool isPending;
}

int? getAdjacentChapterSortNum({
  required int sortNum,
  required int totalChapters,
  required bool next,
}) {
  final target = next ? sortNum + 1 : sortNum - 1;
  return target >= 1 && target <= totalChapters ? target : null;
}

int resolveReaderInitialIndex(
  ReaderOpenPosition openPosition,
  int savedIndex,
  int totalItems,
) {
  final lastIndex = math.max(0, totalItems - 1);
  return switch (openPosition) {
    ReaderOpenPosition.start => 0,
    ReaderOpenPosition.end => lastIndex,
    ReaderOpenPosition.saved => math.min(lastIndex, math.max(0, savedIndex)),
  };
}

/// 未同步的本地进度优先，已同步的仅作兜底，跨设备以服务端为准。
ReaderRestorePosition? resolveReaderRestorePosition(
  int chapterId,
  ReaderRestorePosition? server,
  CachedReaderRestorePosition? cached, {
  bool preferCached = false,
}) {
  final local = cached != null && cached.chapterId == chapterId ? cached : null;
  final remote = server != null && server.chapterId == chapterId
      ? server
      : null;
  if (local != null && (local.isPending || preferCached)) return local;
  return remote ?? local;
}

/// 打开章节时的续读位置：把进程内缓存与服务端返回的两种形态归一后交给
/// [resolveReaderRestorePosition]。
ReaderRestorePosition? resolveReaderRestore({
  required int bookId,
  required int chapterId,
  BookReadPosition? server,
}) {
  final cached = ReadPositionCache.read(bookId);
  return resolveReaderRestorePosition(
    chapterId,
    server == null
        ? null
        : ReaderRestorePosition(
            chapterId: server.chapterId,
            position: server.position,
          ),
    cached == null
        ? null
        : CachedReaderRestorePosition(
            chapterId: cached.chapterId,
            position: cached.position,
          ),
  );
}

final RegExp _locatorHeadPattern = RegExp(r'^/?/?\*?/?');
final RegExp _locatorEdgeSlashPattern = RegExp(r'^/+|/+$');

String cleanReaderLocator(String locator) => locator
    .replaceFirst(_locatorHeadPattern, '')
    .replaceAll(_locatorEdgeSlashPattern, '');

/// 定位失配时逐级回退父路径，落到最近的段落。
int findReaderBlockIndex(List<NovelReaderBlock> blocks, String? locator) {
  if (locator == null || locator.isEmpty) return 0;
  final exact = blocks.indexWhere(
    (block) => block.locator == locator || block.id == locator,
  );
  if (exact >= 0) return exact;

  final indexByLocator = <String, int>{
    for (var index = 0; index < blocks.length; index++)
      cleanReaderLocator(blocks[index].locator): index,
  };
  var candidate = cleanReaderLocator(locator);
  while (candidate.isNotEmpty) {
    final index = indexByLocator[candidate];
    if (index != null) return index;
    final slash = candidate.lastIndexOf('/');
    if (slash < 0) break;
    candidate = candidate.substring(0, slash);
  }
  return 0;
}
