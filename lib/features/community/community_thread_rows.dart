import 'package:flutter/foundation.dart';

import '../../data/api/models.dart';

enum CommunityThreadRowKind { parent, child, more }

/// 回复树摊平后的一行，`more` 行是某个主楼下的「展开更多回复」。
@immutable
class CommunityThreadRow {
  const CommunityThreadRow({
    required this.kind,
    required this.parent,
    this.reply,
    this.closesGroup = false,
  });

  final CommunityThreadRowKind kind;
  final CommunityThreadReply parent;
  final CommunityThreadReply? reply;
  final bool closesGroup;
}

/// 主楼、子级、「展开更多」按同一列顺序摊平，列表按行回收。
List<CommunityThreadRow> flattenReplyRows(CommunityThreadDetail? detail) {
  if (detail == null) return const <CommunityThreadRow>[];
  final rows = <CommunityThreadRow>[];
  for (final CommunityThreadReply parent in detail.replyItems) {
    final hasMore = parent.childPage.hasMore;
    final children = parent.childReplies;
    rows.add(
      CommunityThreadRow(
        kind: CommunityThreadRowKind.parent,
        parent: parent,
        reply: parent,
        closesGroup: children.isEmpty && !hasMore,
      ),
    );
    for (int index = 0; index < children.length; index += 1) {
      rows.add(
        CommunityThreadRow(
          kind: CommunityThreadRowKind.child,
          parent: parent,
          reply: children[index],
          closesGroup: index == children.length - 1 && !hasMore,
        ),
      );
    }
    if (hasMore) {
      rows.add(
        CommunityThreadRow(
          kind: CommunityThreadRowKind.more,
          parent: parent,
          closesGroup: true,
        ),
      );
    }
  }
  return rows;
}
