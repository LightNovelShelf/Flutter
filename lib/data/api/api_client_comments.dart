import 'api_client.dart';
import 'models.dart';

/// 书籍/公告/漫画系列下的评论区。
extension ApiClientComments on ApiClient {
  Future<CommentPage> getComments({
    required CommentTargetType type,
    required int id,
    required int page,
    int size = 10,
    String? seriesTitle,
  }) => invoke('GetComments', <String, Object?>{
    'Type': type.wire,
    'Id': id,
    'Page': page,
    'Size': size,
    'SeriesTitle': ?seriesTitle,
  }, CommentPage.decode);

  Future<void> postComment({
    required CommentTargetType type,
    required int id,
    required String content,
    String? seriesTitle,
  }) => invoke(
    'PostComment',
    _encodeComment(
      type: type,
      id: id,
      content: content,
      seriesTitle: seriesTitle,
    ),
    (_) {},
  );

  Future<void> replyComment({
    required CommentTargetType type,
    required int id,
    required String content,
    String? seriesTitle,
    int? parentId,
    int? replyId,
  }) => invoke(
    'ReplyComment',
    _encodeComment(
      type: type,
      id: id,
      content: content,
      seriesTitle: seriesTitle,
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
  String? seriesTitle,
  int? parentId,
  int? replyId,
}) => <String, Object?>{
  'Type': type.wire,
  'Id': id,
  'Content': content,
  'SeriesTitle': ?seriesTitle,
  'ParentId': ?parentId,
  'ReplyId': ?replyId,
};
