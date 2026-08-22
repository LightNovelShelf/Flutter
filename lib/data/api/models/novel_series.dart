import '../decode.dart';

/// 小说系列列表项。分组键是服务端分类器给出的系列名（中文名优先，为空回落原名、
/// 再回落书名），没有独立 id。
class NovelSeriesListItem {
  const NovelSeriesListItem({
    required this.name,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.bookCount,
    required this.lastUpdatedAt,
  });

  final String name;

  /// 系列内最新一本的封面，服务端取不到时为空串。
  final String coverUrl;
  final String? coverPlaceholder;
  final int bookCount;
  final DateTime lastUpdatedAt;

  static NovelSeriesListItem decode(Object? value) {
    final series = asRecord(value, '小说系列列表项');
    final rawCover = asNullableString(series['Cover']);
    final cover = rawCover == null ? null : decodeCover(rawCover);
    return NovelSeriesListItem(
      name: asString(series['Name']),
      coverUrl: cover?.url ?? '',
      coverPlaceholder: cover?.placeholder,
      bookCount: asCount(series['Count']),
      lastUpdatedAt: asDate(series['LastUpdatedAt']),
    );
  }
}

class NovelSeriesListPage {
  const NovelSeriesListPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<NovelSeriesListItem> items;

  static NovelSeriesListPage decode(Object? value) {
    final record = asRecord(value, '小说系列列表响应');
    return NovelSeriesListPage(
      page: asInt(record['Page'], 1),
      totalPages: asInt(record['TotalPages'], 1),
      items: asArray(
        record['Data'],
        '小说系列列表项',
      ).map(NovelSeriesListItem.decode).toList(),
    );
  }
}
