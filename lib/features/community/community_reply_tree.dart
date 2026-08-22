import '../../data/api/models.dart';

CommunityThreadReply? findReply(List<CommunityThreadReply> items, int id) {
  for (final CommunityThreadReply reply in items) {
    if (reply.id == id) return reply;
    final child = findReply(reply.childReplies, id);
    if (child != null) return child;
  }
  return null;
}

/// 命中 id 就替换，否则递归子回复。
List<CommunityThreadReply> updateReplies(
  List<CommunityThreadReply> items,
  int id,
  CommunityThreadReply Function(CommunityThreadReply reply) update,
) => items
    .map((reply) {
      if (reply.id == id) return update(reply);
      if (reply.childReplies.isEmpty) return reply;
      return reply.copyWith(
        childReplies: updateReplies(reply.childReplies, id, update),
      );
    })
    .toList(growable: false);
