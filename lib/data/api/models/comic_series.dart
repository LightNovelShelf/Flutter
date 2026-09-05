import '../decode.dart';
import 'book.dart';

class ComicSeriesListItem {
  const ComicSeriesListItem({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.chapterCount,
    required this.lastUpdatedAt,
  });

  final int id;
  final String title;
  final String? originalTitle;
  final String coverUrl;
  final String? coverPlaceholder;
  final int chapterCount;
  final DateTime lastUpdatedAt;

  static ComicSeriesListItem decode(Object? value) {
    final comic = asRecord(value, '漫画系列列表项');
    final cover = decodeCover(comic['Cover']);
    return ComicSeriesListItem(
      id: asInt(comic['Id']),
      title: asString(comic['Title']),
      originalTitle: asNullableString(comic['OriginalTitle']),
      coverUrl: cover.url,
      coverPlaceholder: cover.placeholder,
      chapterCount: asCount(comic['Count']),
      lastUpdatedAt: asDate(comic['LastUpdatedAt']),
    );
  }

  /// 转为通用书卡，与小说共用网格卡片。
  BookListItem toBookListItem() => BookListItem(
    id: id,
    type: BookType.comic,
    title: title,
    coverUrl: coverUrl,
    coverPlaceholder: coverPlaceholder,
    authorName: null,
    lastUpdatedAt: lastUpdatedAt,
    level: null,
    interiorLevel: null,
    category: null,
  );
}

class ComicSeriesListPage {
  const ComicSeriesListPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<ComicSeriesListItem> items;

  static ComicSeriesListPage decode(Object? value) {
    final record = asRecord(value, '漫画系列列表响应');
    return ComicSeriesListPage(
      page: asInt(record['Page'], 1),
      totalPages: asInt(record['TotalPages'], 1),
      items: asArray(
        record['Data'],
        '漫画系列列表项',
      ).map(ComicSeriesListItem.decode).toList(),
    );
  }
}
