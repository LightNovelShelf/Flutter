import '../decode.dart';

enum AppNotificationTone { neutral, info, success, warning, danger }

AppNotificationTone _decodeNotificationTone(Object? value) => switch (value) {
  'info' => AppNotificationTone.info,
  'success' => AppNotificationTone.success,
  'warning' => AppNotificationTone.warning,
  'danger' => AppNotificationTone.danger,
  _ => AppNotificationTone.neutral,
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

  static AppNotificationActor? decode(Object? value) {
    final actor = asRecordOrNull(value);
    if (actor == null) return null;
    return AppNotificationActor(
      id: asInt(actor['Id']),
      userName: asStringOrEmpty(actor['UserName']),
      avatar: asStringOrEmpty(actor['Avatar']),
    );
  }
}

class AppNotificationAction {
  const AppNotificationAction({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;

  static AppNotificationAction? decode(Object? value) {
    final action = asRecordOrNull(value);
    if (action == null) return null;
    final type = asStringOrEmpty(action['Type']);
    if (type.isEmpty) return null;
    return AppNotificationAction(
      type: type,
      data: asRecordOrEmpty(action['Data']),
    );
  }
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.actor,
    required this.kind,
    required this.schemaVersion,
    required this.title,
    required this.body,
    required this.tone,
    required this.action,
    required this.data,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
  });

  final int id;
  final AppNotificationActor? actor;
  final String kind;
  final int schemaVersion;
  final String title;
  final String body;
  final AppNotificationTone tone;
  final AppNotificationAction? action;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;

  AppNotificationItem copyWith({bool? isRead, DateTime? readAt}) =>
      AppNotificationItem(
        id: id,
        actor: actor,
        kind: kind,
        schemaVersion: schemaVersion,
        title: title,
        body: body,
        tone: tone,
        action: action,
        data: data,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );

  static AppNotificationItem decode(Object? value) {
    final item = asRecord(value, '通知');
    return AppNotificationItem(
      id: asInt(item['Id']),
      actor: AppNotificationActor.decode(item['Actor']),
      kind: asStringOrEmpty(item['Kind']),
      schemaVersion: asInt(item['SchemaVersion'], 1),
      title: asStringOrEmpty(item['Title']),
      body: asStringOrEmpty(item['Body']),
      tone: _decodeNotificationTone(item['Tone']),
      action: AppNotificationAction.decode(item['Action']),
      data: asRecordOrEmpty(item['Data']),
      isRead: asBool(item['IsRead'], false),
      readAt: asNullableDate(item['ReadAt']),
      createdAt: asNullableDate(item['CreatedAt']),
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
