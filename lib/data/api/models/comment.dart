import '../decode.dart';

enum CommentTargetType { book, announcement }

/// 枚举型参数按服务端枚举名发送（服务端已挂 `JsonStringEnumConverter`），
/// 名字比序号更抗成员重排。
extension CommentTargetTypeWire on CommentTargetType {
  String get wire => switch (this) {
    CommentTargetType.book => 'Book',
    CommentTargetType.announcement => 'Announcement',
  };
}

class CommentUser {
  const CommentUser({
    required this.id,
    required this.userName,
    required this.avatarUrl,
  });

  final int id;
  final String userName;
  final String avatarUrl;
}

class CommentReply {
  const CommentReply({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    required this.replyToUser,
  });

  final int id;
  final CommentUser user;
  final String content;
  final DateTime createdAt;
  final bool canEdit;
  final CommentUser? replyToUser;
}

class CommentItem {
  const CommentItem({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    required this.replies,
  });

  final int id;
  final CommentUser user;
  final String content;
  final DateTime createdAt;
  final bool canEdit;
  final List<CommentReply> replies;
}

class CommentPage {
  const CommentPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<CommentItem> items;

  static CommentPage decode(Object? value) {
    final response = asRecord(value, '评论响应');
    final users = asRecord(response['Users'], '评论用户');
    final commentaries = asRecord(response['Commentaries'], '评论内容');
    final roots = asArray(response['Data'], '评论根节点');

    CommentUser getUser(int userId) {
      final user = asRecord(users['$userId'], '评论用户');
      return CommentUser(
        id: asInt(user['Id'], userId),
        userName: asString(user['UserName']),
        avatarUrl: asStringOrEmpty(user['Avatar']),
      );
    }

    Map<String, dynamic> getCommentary(int commentId) =>
        asRecord(commentaries['$commentId'], '评论内容');

    return CommentPage(
      page: asInt(response['Page'], 1),
      totalPages: asInt(response['TotalPages'], 0),
      items: roots.map((rootValue) {
        final root = asRecord(rootValue, '评论根节点');
        final id = asInt(root['Id']);
        final commentary = getCommentary(id);
        final replyIds = decodeOptionalList(root['Reply'], '评论回复', asInt);
        return CommentItem(
          id: id,
          user: getUser(asInt(commentary['UserId'])),
          content: asStringOrEmpty(commentary['Content']),
          createdAt: asDate(commentary['CreatedAt']),
          canEdit: asBool(commentary['CanEdit'], false),
          replies: replyIds.map((replyId) {
            final reply = getCommentary(replyId);
            final replyToId = asNullableInt(reply['ReplyId']);
            final replyTo = replyToId == null ? null : getCommentary(replyToId);
            return CommentReply(
              id: replyId,
              user: getUser(asInt(reply['UserId'])),
              content: asStringOrEmpty(reply['Content']),
              createdAt: asDate(reply['CreatedAt']),
              canEdit: asBool(reply['CanEdit'], false),
              replyToUser: replyTo == null
                  ? null
                  : getUser(asInt(replyTo['UserId'])),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
