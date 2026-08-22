import '../decode.dart';

enum AppNotificationType {
  comment,
  commentReply,
  communityThreadReply,
  communityThreadChildReply,
  unknown,
}

AppNotificationType _decodeNotificationType(Object? value) => switch (value) {
  'Comment' => AppNotificationType.comment,
  'CommentReply' => AppNotificationType.commentReply,
  'CommunityThreadReply' => AppNotificationType.communityThreadReply,
  'CommunityThreadChildReply' => AppNotificationType.communityThreadChildReply,
  _ => AppNotificationType.unknown,
};

enum AppNotificationObjectType {
  book,
  announcement,
  communityThread,
  series,
  unknown,
}

AppNotificationObjectType _decodeNotificationObjectType(Object? value) =>
    switch (value) {
      'Book' => AppNotificationObjectType.book,
      'Announcement' => AppNotificationObjectType.announcement,
      'CommunityThread' => AppNotificationObjectType.communityThread,
      'Series' => AppNotificationObjectType.series,
      _ => AppNotificationObjectType.unknown,
    };

class AppNotificationActor {
  const AppNotificationActor({
    required this.id,
    required this.userName,
    required this.avatar,
  });

  final int id;
  final String userName;
  final String avatar;
}

class AppNotificationExtra {
  const AppNotificationExtra({
    required this.objectId,
    required this.objectTitle,
    required this.seriesTitle,
    required this.preview,
    required this.replyId,
    required this.parentReplyId,
    required this.replyToReplyId,
    required this.replyPreview,
  });

  final int objectId;
  final String objectTitle;
  final String? seriesTitle;
  final String preview;
  final int? replyId;
  final int? parentReplyId;
  final int? replyToReplyId;
  final String? replyPreview;
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.actor,
    required this.type,
    required this.objectType,
    required this.objectId,
    required this.isRead,
    required this.createdAt,
    required this.extra,
  });

  final int id;
  final AppNotificationActor? actor;
  final AppNotificationType type;
  final AppNotificationObjectType objectType;
  final int objectId;
  final bool isRead;
  final DateTime? createdAt;
  final AppNotificationExtra extra;

  AppNotificationItem copyWith({bool? isRead}) => AppNotificationItem(
    id: id,
    actor: actor,
    type: type,
    objectType: objectType,
    objectId: objectId,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    extra: extra,
  );

  static AppNotificationItem decode(Object? value) {
    final item = asRecord(value, '通知');
    final actor = asRecordOrNull(item['Actor']);
    final extra = asRecordOrEmpty(item['Extra']);
    return AppNotificationItem(
      id: asInt(item['Id']),
      actor: actor == null
          ? null
          : AppNotificationActor(
              id: asInt(actor['Id']),
              userName: asStringOrEmpty(actor['UserName']),
              avatar: asStringOrEmpty(actor['Avatar']),
            ),
      type: _decodeNotificationType(item['Type']),
      objectType: _decodeNotificationObjectType(item['ObjectType']),
      objectId: asInt(item['ObjectId'], 0),
      isRead: asBool(item['IsRead'], false),
      createdAt: asNullableDate(item['CreatedAt']),
      extra: AppNotificationExtra(
        objectId: asInt(extra['object_id'], 0),
        objectTitle: asStringOrEmpty(extra['object_title']),
        seriesTitle: asNullableString(extra['series_title']),
        preview: asStringOrEmpty(extra['preview']),
        replyId: asNullableInt(extra['reply_id']),
        parentReplyId: asNullableInt(extra['parent_reply_id']),
        replyToReplyId: asNullableInt(extra['reply_to_reply_id']),
        replyPreview: asNullableString(extra['reply_preview']),
      ),
    );
  }
}

class AppNotificationPage {
  const AppNotificationPage({
    required this.totalPages,
    required this.page,
    required this.items,
  });

  final int totalPages;
  final int page;
  final List<AppNotificationItem> items;

  static AppNotificationPage decode(Object? value) {
    final response = asRecord(value, '通知响应');
    return AppNotificationPage(
      totalPages: asCount(response['TotalPages']),
      page: asInt(response['Page'], 1).clamp(1, 1 << 30),
      items: decodeOptionalList(
        response['Data'],
        '通知列表',
        AppNotificationItem.decode,
      ),
    );
  }
}
