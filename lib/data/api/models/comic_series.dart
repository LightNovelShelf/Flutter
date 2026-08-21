import '../decode.dart';
import 'book.dart';
import 'comic.dart';
import 'read_position.dart';

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

  /// 把漫画系列映射到通用书卡形状，让小说与漫画共用同一个网格卡片。
  BookListItem toBookListItem() => BookListItem(
    id: id,
    type: BookType.comic,
    title: title,
    seriesTitle: null,
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

class ComicSeriesVolume {
  const ComicSeriesVolume({
    required this.id,
    required this.title,
    required this.uploaderName,
    required this.uploaderAvatarUrl,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.createdAt,
    required this.lastUpdatedChapter,
    required this.lastUpdatedAt,
    required this.readPosition,
    required this.chapters,
  });

  final int id;
  final String title;
  final String uploaderName;
  final String uploaderAvatarUrl;
  final String coverUrl;
  final String? coverPlaceholder;
  final DateTime createdAt;
  final String? lastUpdatedChapter;
  final DateTime lastUpdatedAt;
  final BookReadPosition? readPosition;
  final List<ComicChapterSummary> chapters;

  static ComicSeriesVolume decode(Object? value) {
    final volume = asRecord(value, '漫画系列分卷');
    final uploader = asRecord(volume['Uploader'], '漫画系列上传者');
    final cover = decodeCover(volume['Cover']);
    return ComicSeriesVolume(
      id: asInt(volume['Id']),
      title: asString(volume['Title']),
      uploaderName: asStringOrEmpty(uploader['UserName']),
      uploaderAvatarUrl: asStringOrEmpty(uploader['Avatar']),
      coverUrl: cover.url,
      coverPlaceholder: cover.placeholder,
      createdAt: asDate(volume['CreatedAt']),
      lastUpdatedChapter: asNullableString(volume['LastUpdatedChapter']),
      lastUpdatedAt: asDate(volume['LastUpdatedAt']),
      readPosition: BookReadPosition.decodeNullable(volume['ReadPosition']),
      chapters: ComicChapterSummary.decodeList(volume['Chapters']),
    );
  }
}

class ComicSeriesDetail {
  const ComicSeriesDetail({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.authorName,
    required this.views,
    required this.favoriteCount,
    required this.introduction,
    required this.createdAt,
    required this.lastUpdatedChapter,
    required this.lastUpdatedAt,
    required this.classification,
    required this.volumes,
  });

  final String id;
  final String title;
  final String? originalTitle;
  final String coverUrl;
  final String? coverPlaceholder;
  final String? authorName;
  final int views;
  final int favoriteCount;
  final String introduction;
  final DateTime createdAt;
  final String? lastUpdatedChapter;
  final DateTime lastUpdatedAt;
  final BookClassification classification;
  final List<ComicSeriesVolume> volumes;

  static ComicSeriesDetail decode(Object? value) {
    final response = asRecord(value, '漫画系列详情响应');
    final series = asRecord(response['Series'], '漫画系列详情');
    final cover = decodeCover(series['Cover']);
    return ComicSeriesDetail(
      id: asString(series['Id']),
      title: asString(series['Title']),
      originalTitle: asNullableString(series['OriginalTitle']),
      coverUrl: cover.url,
      coverPlaceholder: cover.placeholder,
      authorName: asNullableString(series['Author']),
      views: asInt(series['Views'], 0),
      favoriteCount: asInt(series['Favorite'], 0),
      introduction: asStringOrEmpty(series['Introduction']),
      createdAt: asDate(series['CreatedAt']),
      lastUpdatedChapter: asNullableString(series['LastUpdatedChapter']),
      lastUpdatedAt: asDate(series['LastUpdatedAt']),
      classification: BookClassification.decode(series['Extra']),
      volumes: asArray(
        response['Books'],
        '漫画系列分卷',
      ).map(ComicSeriesVolume.decode).toList(),
    );
  }
}
