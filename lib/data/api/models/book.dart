import '../decode.dart';
import 'read_position.dart';

/// 书籍类型。
enum BookType { novel, comic }

BookType? _decodeBookType(Object? value) {
  if (value == 'Comic' || value == 1) return BookType.comic;
  if (value == 'Novel' || value == 0) return BookType.novel;
  return null;
}

/// `BookType` 的线上表示，按服务端枚举名发送。
extension BookTypeWire on BookType {
  String get wire => switch (this) {
    BookType.novel => 'Novel',
    BookType.comic => 'Comic',
  };
}

class BookCategory {
  const BookCategory({
    required this.name,
    required this.shortName,
    required this.color,
  });

  final String name;
  final String shortName;
  final String color;

  static BookCategory? decodeNullable(Object? value) {
    if (value == null) return null;
    final record = asRecord(value, '书籍分类');
    return BookCategory(
      name: asString(record['Name']),
      shortName: asString(record['ShortName']),
      color: asString(record['Color']),
    );
  }
}

class BookListItem {
  const BookListItem({
    required this.id,
    required this.type,
    required this.title,
    required this.seriesTitle,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.authorName,
    required this.lastUpdatedAt,
    required this.level,
    required this.interiorLevel,
    required this.category,
  });

  final int id;
  final BookType? type;
  final String title;
  final String? seriesTitle;
  final String coverUrl;
  final String? coverPlaceholder;
  final String? authorName;
  final DateTime lastUpdatedAt;
  final int? level;
  final int? interiorLevel;
  final BookCategory? category;

  static BookListItem decode(Object? value) {
    final book = asRecord(value, '书籍列表项');
    final cover = decodeCover(book['Cover']);
    return BookListItem(
      id: asInt(book['Id']),
      // 未知 Type 在列表里按小说渲染。
      type: _decodeBookType(book['Type']) ?? BookType.novel,
      title: asString(book['Title']),
      seriesTitle: asNullableString(book['SeriesTitle']),
      coverUrl: cover.url,
      coverPlaceholder: cover.placeholder,
      authorName: asNullableString(book['UserName']),
      lastUpdatedAt: asDate(book['LastUpdatedAt']),
      level: asNullableInt(book['Level']),
      interiorLevel: asNullableInt(book['InteriorLevel']),
      category: BookCategory.decodeNullable(book['Category']),
    );
  }
}

class BookListPage {
  const BookListPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<BookListItem> items;

  static BookListPage decode(Object? value) {
    final record = asRecord(value, '书籍列表响应');
    return BookListPage(
      page: asInt(record['Page'], 1),
      totalPages: asInt(record['TotalPages'], 1),
      items: asArray(record['Data'], '书籍列表项').map(BookListItem.decode).toList(),
    );
  }
}

/// 列表接口可能直接返回数组，也可能包一层分页对象。
List<dynamic> _rawBookListItems(Object? value) =>
    value is List ? value : asArray(asRecordOrEmpty(value)['Data'], '书籍列表数据');

List<BookListItem> decodeBookListItems(Object? value) =>
    _rawBookListItems(value).map(BookListItem.decode).toList();

/// `GetBookListByIds` 会用占位符保留未解析的位置，跳过它们。
List<BookListItem> decodeResolvableBookListItems(Object? value) =>
    _rawBookListItems(value)
        .where((item) => asRecordOrNull(item) != null)
        .map(BookListItem.decode)
        .toList();

class BookChapter {
  const BookChapter({required this.id, required this.title});

  final int id;
  final String title;
}

class BookClassification {
  const BookClassification({
    required this.author,
    required this.seriesName,
    required this.seriesNameCn,
    required this.tags,
  });

  final String? author;
  final String? seriesName;
  final String? seriesNameCn;
  final List<String> tags;

  static const BookClassification empty = BookClassification(
    author: null,
    seriesName: null,
    seriesNameCn: null,
    tags: <String>[],
  );

  static BookClassification decode(Object? value) {
    final record = asRecordOrNull(value);
    final classification = asRecordOrNull(record?['classification']);
    if (classification == null) return empty;
    return BookClassification(
      author: asNullableString(classification['author']),
      seriesName: asNullableString(classification['series_name']),
      seriesNameCn: asNullableString(classification['series_name_cn']),
      tags: decodeStringList(classification['tags']),
    );
  }
}

class BookDetailUser {
  const BookDetailUser({
    required this.id,
    required this.userName,
    required this.avatarUrl,
  });

  final int id;
  final String userName;
  final String avatarUrl;

  static BookDetailUser? decodeNullable(Object? value) {
    final record = asRecordOrNull(value);
    if (record == null) return null;
    return BookDetailUser(
      id: asInt(record['Id']),
      userName: asString(record['UserName']),
      avatarUrl: asStringOrEmpty(record['Avatar']),
    );
  }
}

class BookDetail {
  const BookDetail({
    required this.id,
    required this.type,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.title,
    required this.authorName,
    required this.category,
    required this.introduction,
    required this.lastUpdatedChapter,
    required this.lastUpdatedAt,
    required this.createdAt,
    required this.favoriteCount,
    required this.viewCount,
    required this.canEdit,
    required this.chapters,
    required this.user,
    required this.classification,
    required this.readPosition,
  });

  final int id;
  final BookType? type;
  final String coverUrl;
  final String? coverPlaceholder;
  final String title;
  final String? authorName;
  final BookCategory? category;
  final String introduction;
  final String? lastUpdatedChapter;
  final DateTime lastUpdatedAt;
  final DateTime createdAt;
  final int favoriteCount;
  final int viewCount;
  final bool canEdit;
  final List<BookChapter> chapters;
  final BookDetailUser? user;
  final BookClassification classification;
  final BookReadPosition? readPosition;

  static List<BookChapter> _decodeChapters(Object? value) =>
      decodeOptionalList(value, '书籍章节', (item) {
        final chapter = asRecord(item, '书籍章节');
        return BookChapter(
          id: asInt(chapter['Id']),
          title: asString(chapter['Title']),
        );
      });

  static BookDetail decode(Object? value) {
    final response = asRecord(value, '书籍详情响应');
    final book = asRecord(response['Book'] ?? response, '书籍详情');
    final cover = decodeCover(book['Cover']);
    return BookDetail(
      id: asInt(book['Id']),
      type: _decodeBookType(book['Type']),
      coverUrl: cover.url,
      coverPlaceholder: cover.placeholder,
      title: asString(book['Title']),
      authorName: asNullableString(book['Author']),
      category: BookCategory.decodeNullable(book['Category']),
      introduction: asStringOrEmpty(book['Introduction']),
      lastUpdatedChapter: asNullableString(book['LastUpdatedChapter']),
      lastUpdatedAt: asDate(book['LastUpdatedAt']),
      createdAt: asDate(book['CreatedAt']),
      favoriteCount: asInt(book['Favorite'], 0),
      viewCount: asInt(book['Views'], 0),
      canEdit: asBool(book['CanEdit'], false),
      chapters: _decodeChapters(book['Chapter']),
      user: BookDetailUser.decodeNullable(book['User']),
      classification: BookClassification.decode(book['Extra']),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }
}
