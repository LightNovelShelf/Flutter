import 'api_client.dart';
import 'models.dart';

/// 书籍或公告下的评论区。
extension ApiClientComments on ApiClient {
  Future<CommentPage> getComments({
    required CommentTargetType type,
    required int id,
    required int page,
    int size = 10,
  }) => invoke('GetComments', <String, Object?>{
    'Type': type.wire,
    'Id': id,
    'Page': page,
    'Size': size,
  }, CommentPage.decode);

  Future<void> postComment({
    required CommentTargetType type,
    required int id,
    required String content,
  }) => invoke(
    'PostComment',
    _encodeComment(type: type, id: id, content: content),
    (_) {},
  );

  Future<void> replyComment({
    required CommentTargetType type,
    required int id,
    required String content,
    int? parentId,
    int? replyId,
  }) => invoke(
    'ReplyComment',
    _encodeComment(
      type: type,
      id: id,
      content: content,
      parentId: parentId,
      replyId: replyId,
    ),
    (_) {},
  );

  Future<void> deleteComment(int id) =>
      invoke('DeleteComment', <String, Object?>{'Id': id}, (_) {});
}

Map<String, Object?> _encodeComment({
  required CommentTargetType type,
  required int id,
  required String content,
  int? parentId,
  int? replyId,
}) => <String, Object?>{
  'Type': type.wire,
  'Id': id,
  'Content': content,
  'ParentId': ?parentId,
  'ReplyId': ?replyId,
};
