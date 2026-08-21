import '../decode.dart';

class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.contentHtml,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final String contentHtml;

  static AnnouncementItem decode(Object? value) {
    final announcement = asRecord(value, '公告项');
    return AnnouncementItem(
      id: asInt(announcement['Id']),
      title: asString(announcement['Title']),
      createdAt: asDate(announcement['CreatedAt']),
      contentHtml: asStringOrEmpty(announcement['Content']),
    );
  }
}

class AnnouncementPage {
  const AnnouncementPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<AnnouncementItem> items;

  static AnnouncementPage decode(Object? value) {
    final record = asRecord(value, '公告响应');
    return AnnouncementPage(
      page: asInt(record['Page'], 1),
      totalPages: asInt(record['TotalPages'], 1),
      items: asArray(
        record['Data'],
        '公告项',
      ).map(AnnouncementItem.decode).toList(),
    );
  }
}
