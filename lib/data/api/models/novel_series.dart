import '../decode.dart';

/// 小说系列列表项：服务端按分类器的系列名分组（中文名优先、空回落原名、再空回落书名），
/// 分组键就是系列名，没有独立 id。
class NovelSeriesListItem {
  const NovelSeriesListItem({
    required this.name,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.bookCount,
    required this.lastUpdatedAt,
  });

  final String name;

  /// 代表封面（系列内最新一本）；服务端偶尔取不到封面，此时为空串。
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
      items: asArray(record['Data'], '小说系列列表项')
          .map(NovelSeriesListItem.decode)
          .toList(),
    );
  }
}
