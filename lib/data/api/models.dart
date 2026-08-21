import '../../core/network/api_error.dart';
import 'decode.dart';

/// 书籍类型。
enum BookType { novel, comic }

BookType? _decodeBookType(Object? value) {
  if (value == 'Comic' || value == 1) return BookType.comic;
  if (value == 'Novel' || value == 0) return BookType.novel;
  return null;
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
    final rawCoverUrl = asString(book['Cover']);
    return BookListItem(
      id: asInt(book['Id']),
      type: book['Type'] == 'Comic' || book['Type'] == 1
          ? BookType.comic
          : BookType.novel,
      title: asString(book['Title']),
      seriesTitle: asNullableString(book['SeriesTitle']),
      coverUrl: normalizeCoverUrl(rawCoverUrl),
      coverPlaceholder: extractBlurHashPlaceholder(rawCoverUrl),
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

List<dynamic> _rawBookListItems(Object? value) {
  if (value is List) return value;
  final record = asRecordOrNull(value);
  if (record != null && record['Data'] is List) {
    return record['Data'] as List<dynamic>;
  }
  throw const ApiError('无效的书籍列表数据。', ApiErrorCategory.server);
}

List<BookListItem> decodeBookListItems(Object? value) =>
    _rawBookListItems(value).map(BookListItem.decode).toList();

/// `GetBookListByIds` 会用占位符保留未解析的位置，跳过它们。
List<BookListItem> decodeResolvableBookListItems(Object? value) =>
    _rawBookListItems(value)
        .where((item) => asRecordOrNull(item) != null)
        .map(BookListItem.decode)
        .toList();

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
    final rawCoverUrl = asString(comic['Cover']);
    return ComicSeriesListItem(
      id: asInt(comic['Id']),
      title: asString(comic['Title']),
      originalTitle: asNullableString(comic['OriginalTitle']),
      coverUrl: normalizeCoverUrl(rawCoverUrl),
      coverPlaceholder: extractBlurHashPlaceholder(rawCoverUrl),
      chapterCount: asInt(comic['Count'], 0).clamp(0, 1 << 30),
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

class ReadHistory {
  const ReadHistory({required this.novelIds, required this.comicIds});

  final List<int> novelIds;
  final List<int> comicIds;

  static ReadHistory decode(Object? value) {
    final record = asRecord(value, '阅读历史响应');
    return ReadHistory(
      novelIds: decodeIntList(record['Novel'], '小说历史'),
      comicIds: decodeIntList(record['Comic'], '漫画历史'),
    );
  }
}

enum ShelfItemType { book, folder }

/// 书架条目：书籍或文件夹。
class ShelfItem {
  const ShelfItem({
    required this.type,
    required this.bookId,
    required this.folderId,
    required this.index,
    required this.parents,
    required this.updatedAt,
    required this.title,
  });

  const ShelfItem.book({
    required int id,
    required this.index,
    required this.parents,
    required this.updatedAt,
  }) : type = ShelfItemType.book,
       bookId = id,
       folderId = null,
       title = '';

  const ShelfItem.folder({
    required String id,
    required this.index,
    required this.parents,
    required this.updatedAt,
    required this.title,
  }) : type = ShelfItemType.folder,
       bookId = null,
       folderId = id;

  final ShelfItemType type;
  final int? bookId;
  final String? folderId;
  final int index;
  final List<String> parents;
  final String updatedAt;
  final String title;

  bool get isBook => type == ShelfItemType.book;

  String get key => isBook ? 'BOOK:$bookId' : 'FOLDER:$folderId';

  ShelfItem copyWith({
    int? index,
    List<String>? parents,
    String? updatedAt,
    String? title,
  }) => ShelfItem(
    type: type,
    bookId: bookId,
    folderId: folderId,
    index: index ?? this.index,
    parents: parents ?? this.parents,
    updatedAt: updatedAt ?? this.updatedAt,
    title: title ?? this.title,
  );

  static ShelfItemType _decodeType(Object? value) {
    if (value == 'BOOK' || value == 'Book' || value == 0) {
      return ShelfItemType.book;
    }
    if (value == 'FOLDER' || value == 'Folder' || value == 1) {
      return ShelfItemType.folder;
    }
    throw const ApiError('服务端返回了无效的书架条目类型。', ApiErrorCategory.server);
  }

  static ShelfItem decode(Object? value) {
    final item = asRecord(value, '书架条目');
    final type = _decodeType(item['type'] ?? item['Type']);
    final index = asInt(item['index'] ?? item['Index'], 0);
    final parents = decodeStringList(item['parents'] ?? item['Parents']);
    final updatedAt = asStringOrEmpty(item['updateAt'] ?? item['UpdateAt']);
    final rawId = item['id'] ?? item['Id'];

    if (type == ShelfItemType.book) {
      return ShelfItem.book(
        id: asInt(rawId),
        index: index,
        parents: parents,
        updatedAt: updatedAt,
      );
    }
    final folderId = rawId is String && rawId.isNotEmpty
        ? rawId
        : rawId is num
        ? rawId.toInt().toString()
        : throw const ApiError('服务端返回了无效的书架条目 ID。', ApiErrorCategory.server);
    return ShelfItem.folder(
      id: folderId,
      index: index,
      parents: parents,
      updatedAt: updatedAt,
      title: asStringOrEmpty(item['title'] ?? item['Title']),
    );
  }

  Map<String, Object?> encode() => <String, Object?>{
    'id': isBook ? bookId : folderId,
    'index': index,
    'parents': parents,
    if (!isBook) 'title': title,
    'type': isBook ? 'BOOK' : 'FOLDER',
    'updateAt': updatedAt,
  };
}

class UserShelf {
  const UserShelf({required this.version, required this.items});

  final String? version;
  final List<ShelfItem> items;

  static UserShelf decode(Object? value) {
    final record = asRecordOrNull(value);
    final rawItems = value is List
        ? value
        : record?['data'] is List
        ? record!['data'] as List<dynamic>
        : record?['Data'] is List
        ? record!['Data'] as List<dynamic>
        : null;
    if (rawItems == null) {
      throw const ApiError('无效的书架响应。', ApiErrorCategory.server);
    }
    final rawVersion = record?['ver'] ?? record?['Ver'];
    return UserShelf(
      version: rawVersion is String || rawVersion is num ? '$rawVersion' : null,
      items: rawItems.map(ShelfItem.decode).toList(),
    );
  }
}

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

class BookReadPosition {
  const BookReadPosition({
    required this.chapterId,
    required this.position,
    this.readAt,
  });

  final int chapterId;
  final String position;
  final DateTime? readAt;

  static BookReadPosition? decodeNullable(Object? value) {
    final record = asRecordOrNull(value);
    if (record == null) return null;
    final chapterId = asInt(record['ChapterId'], 0);
    if (chapterId <= 0) return null;
    return BookReadPosition(
      chapterId: chapterId,
      position: asStringOrEmpty(record['Position']),
      readAt: asNullableDate(record['ReadAt']),
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

  static List<BookChapter> _decodeChapters(Object? value) {
    if (value is! List) return const <BookChapter>[];
    return value.map((item) {
      final chapter = asRecord(item, '书籍章节');
      return BookChapter(
        id: asInt(chapter['Id']),
        title: asString(chapter['Title']),
      );
    }).toList();
  }

  static BookDetail decode(Object? value) {
    final response = asRecord(value, '书籍详情响应');
    final book = asRecord(response['Book'] ?? response, '书籍详情');
    final rawCoverUrl = asString(book['Cover']);
    return BookDetail(
      id: asInt(book['Id']),
      type: _decodeBookType(book['Type']),
      coverUrl: normalizeCoverUrl(rawCoverUrl),
      coverPlaceholder: extractBlurHashPlaceholder(rawCoverUrl),
      title: asString(book['Title']),
      authorName: asNullableString(book['Author']),
      category: BookCategory.decodeNullable(book['Category']),
      introduction: asStringOrEmpty(book['Introduction']),
      lastUpdatedChapter: asNullableString(book['LastUpdatedChapter']),
      lastUpdatedAt: asDate(book['LastUpdatedAt']),
      createdAt: asDate(book['CreatedAt']),
      favoriteCount: asInt(book['Favorite'], 0),
      viewCount: asInt(book['Views'], 0),
      canEdit: book['CanEdit'] == true,
      chapters: _decodeChapters(book['Chapter']),
      user: BookDetailUser.decodeNullable(book['User']),
      classification: BookClassification.decode(book['Extra']),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }
}

class NovelChapterContent {
  const NovelChapterContent({
    required this.id,
    required this.bookId,
    required this.title,
    required this.content,
    required this.fontUrl,
    required this.sortNum,
    required this.chapterTitles,
    required this.canEdit,
  });

  final int id;
  final int bookId;
  final String title;
  final String content;
  final String? fontUrl;
  final int sortNum;
  final List<String> chapterTitles;
  final bool canEdit;
}

class NovelContent {
  const NovelContent({required this.chapter, required this.readPosition});

  final NovelChapterContent chapter;
  final BookReadPosition? readPosition;

  static NovelContent decode(Object? value) {
    final response = asRecord(value, '小说正文响应');
    final chapter = asRecord(response['Chapter'], '小说章节');
    return NovelContent(
      chapter: NovelChapterContent(
        id: asInt(chapter['Id']),
        bookId: asInt(chapter['BookId'], 0),
        title: asString(chapter['Title']),
        content: asStringOrEmpty(chapter['Content']),
        fontUrl: asNullableString(chapter['Font']),
        sortNum: asInt(chapter['SortNum']),
        chapterTitles: decodeStringList(chapter['Chapters']),
        canEdit: chapter['CanEdit'] == true,
      ),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }
}

class ComicChapterSummary {
  const ComicChapterSummary({
    required this.id,
    required this.sortNum,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.pageCount,
  });

  final int id;
  final int sortNum;
  final String title;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int pageCount;

  static List<ComicChapterSummary> decodeList(Object? value) {
    if (value is! List) return const <ComicChapterSummary>[];
    return value.map((item) {
      final chapter = asRecord(item, '漫画章节');
      return ComicChapterSummary(
        id: asInt(chapter['Id']),
        sortNum: asInt(chapter['SortNum']),
        title: asString(chapter['Title']),
        createdAt: asDate(chapter['CreatedAt']),
        updatedAt: asNullableDate(chapter['UpdatedAt']),
        pageCount: asInt(chapter['PageCount'], 0).clamp(0, 1 << 30),
      );
    }).toList();
  }
}

class ComicImage {
  const ComicImage({required this.url, required this.placeholder});

  final String url;
  final String placeholder;

  static ComicImage decode(Object? value) {
    final rawUrl = asString(value);
    return ComicImage(
      url: normalizeCoverUrl(rawUrl),
      placeholder: extractBlurHashPlaceholder(rawUrl) ?? '',
    );
  }
}

class ComicInfo {
  const ComicInfo({
    required this.id,
    required this.coverUrl,
    required this.coverPlaceholder,
    required this.title,
    required this.authorName,
    required this.views,
    required this.introduction,
    required this.createdAt,
    required this.lastUpdatedChapter,
    required this.lastUpdatedAt,
    required this.favoriteCount,
    required this.user,
    required this.classification,
    required this.chapters,
    required this.readPosition,
  });

  final int id;
  final String coverUrl;
  final String? coverPlaceholder;
  final String title;
  final String? authorName;
  final int views;
  final String introduction;
  final DateTime createdAt;
  final String? lastUpdatedChapter;
  final DateTime lastUpdatedAt;
  final int favoriteCount;
  final BookDetailUser? user;
  final BookClassification classification;
  final List<ComicChapterSummary> chapters;
  final BookReadPosition? readPosition;

  static ComicInfo decode(Object? value) {
    final response = asRecord(value, '漫画信息响应');
    final book = asRecord(response['Book'] ?? response, '漫画信息');
    final rawCoverUrl = asString(book['Cover']);
    return ComicInfo(
      id: asInt(book['Id']),
      coverUrl: normalizeCoverUrl(rawCoverUrl),
      coverPlaceholder: extractBlurHashPlaceholder(rawCoverUrl),
      title: asString(book['Title']),
      authorName: asNullableString(book['Author']),
      views: asInt(book['Views'], 0),
      introduction: asStringOrEmpty(book['Introduction']),
      createdAt: asDate(book['CreatedAt']),
      lastUpdatedChapter: asNullableString(book['LastUpdatedChapter']),
      lastUpdatedAt: asDate(book['LastUpdatedAt']),
      favoriteCount: asInt(book['Favorite'], 0),
      user: BookDetailUser.decodeNullable(book['User']),
      classification: BookClassification.decode(book['Extra']),
      chapters: ComicChapterSummary.decodeList(book['Chapters']),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }

  /// 归一化为 `BookDetail`，让详情页对小说/漫画使用同一套 UI。
  /// 漫画章节的排序号由章节顺序推导（1..N），与阅读器的解析方式一致。
  BookDetail toBookDetail() => BookDetail(
    id: id,
    type: BookType.comic,
    coverUrl: coverUrl,
    coverPlaceholder: coverPlaceholder,
    title: title,
    authorName: authorName,
    category: null,
    introduction: introduction,
    lastUpdatedChapter: lastUpdatedChapter,
    lastUpdatedAt: lastUpdatedAt,
    createdAt: createdAt,
    favoriteCount: favoriteCount,
    viewCount: views,
    canEdit: false,
    chapters: chapters
        .map((chapter) => BookChapter(id: chapter.id, title: chapter.title))
        .toList(),
    user: user,
    classification: classification,
    readPosition: readPosition,
  );
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
    final rawCoverUrl = asString(volume['Cover']);
    return ComicSeriesVolume(
      id: asInt(volume['Id']),
      title: asString(volume['Title']),
      uploaderName: asStringOrEmpty(uploader['UserName']),
      uploaderAvatarUrl: asStringOrEmpty(uploader['Avatar']),
      coverUrl: normalizeCoverUrl(rawCoverUrl),
      coverPlaceholder: extractBlurHashPlaceholder(rawCoverUrl),
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
    final rawCoverUrl = asString(series['Cover']);
    return ComicSeriesDetail(
      id: '${series['Id']}',
      title: asString(series['Title']),
      originalTitle: asNullableString(series['OriginalTitle']),
      coverUrl: normalizeCoverUrl(rawCoverUrl),
      coverPlaceholder: extractBlurHashPlaceholder(rawCoverUrl),
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

class ComicContentChapter {
  const ComicContentChapter({
    required this.id,
    required this.bookId,
    required this.bookName,
    required this.title,
    required this.sortNum,
    required this.total,
    required this.skip,
    required this.images,
  });

  final int id;
  final int bookId;
  final String bookName;
  final String title;
  final int sortNum;
  final int total;
  final int skip;
  final List<ComicImage> images;
}

class ComicContent {
  const ComicContent({required this.chapter, required this.readPosition});

  final ComicContentChapter chapter;
  final BookReadPosition? readPosition;

  static ComicContent decode(Object? value) {
    final response = asRecord(value, '漫画正文响应');
    final chapter = asRecord(response['Chapter'], '漫画正文章节');
    final images = chapter['Images'] is List
        ? (chapter['Images'] as List<dynamic>)
        : const <dynamic>[];
    return ComicContent(
      chapter: ComicContentChapter(
        id: asInt(chapter['Id']),
        bookId: asInt(chapter['BookId']),
        bookName: asStringOrEmpty(chapter['BookName']),
        title: asString(chapter['Title']),
        sortNum: asInt(chapter['SortNum']),
        total: asInt(chapter['Total'], images.length).clamp(0, 1 << 30),
        skip: asInt(chapter['Skip'], 0).clamp(0, 1 << 30),
        images: images.map(ComicImage.decode).toList(),
      ),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }
}

enum CommentTargetType { book, announcement, series }

/// 枚举型参数按服务端枚举名发送：JSON 协议已挂上 `JsonStringEnumConverter`，
/// 名字比序号更抗重排（枚举中间插一个成员不会让旧客户端指向错的值）。
extension CommentTargetTypeWire on CommentTargetType {
  String get wire => switch (this) {
    CommentTargetType.book => 'Book',
    CommentTargetType.announcement => 'Announcement',
    CommentTargetType.series => 'Series',
  };
}

/// `BookType` 的线上表示，用途同上。
extension BookTypeWire on BookType {
  String get wire => switch (this) {
    BookType.novel => 'Novel',
    BookType.comic => 'Comic',
  };
}

class CommentUser {
  const CommentUser({
    required this.id,
    required this.userName,
    required this.avatarUrl,
  });

  final int id;
  final String userName;
  final String avatarUrl;
}

class CommentReply {
  const CommentReply({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    required this.replyToUser,
  });

  final int id;
  final CommentUser user;
  final String content;
  final DateTime createdAt;
  final bool canEdit;
  final CommentUser? replyToUser;
}

class CommentItem {
  const CommentItem({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    required this.replies,
  });

  final int id;
  final CommentUser user;
  final String content;
  final DateTime createdAt;
  final bool canEdit;
  final List<CommentReply> replies;
}

class CommentPage {
  const CommentPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<CommentItem> items;

  static CommentPage decode(Object? value) {
    final response = asRecord(value, '评论响应');
    final users = asRecord(response['Users'], '评论用户');
    final commentaries = asRecord(response['Commentaries'], '评论内容');
    final roots = asArray(response['Data'], '评论根节点');

    CommentUser getUser(int userId) {
      final user = asRecord(users['$userId'], '评论用户');
      return CommentUser(
        id: asInt(user['Id'], userId),
        userName: asString(user['UserName']),
        avatarUrl: asStringOrEmpty(user['Avatar']),
      );
    }

    Map<String, dynamic> getCommentary(int commentId) =>
        asRecord(commentaries['$commentId'], '评论内容');

    return CommentPage(
      page: asInt(response['Page'], 1),
      totalPages: asInt(response['TotalPages'], 0),
      items: roots.map((rootValue) {
        final root = asRecord(rootValue, '评论根节点');
        final id = asInt(root['Id']);
        final commentary = getCommentary(id);
        final replyIds = root['Reply'] is List
            ? (root['Reply'] as List<dynamic>).map(asInt).toList()
            : <int>[];
        return CommentItem(
          id: id,
          user: getUser(asInt(commentary['UserId'])),
          content: asStringOrEmpty(commentary['Content']),
          createdAt: asDate(commentary['CreatedAt']),
          canEdit: commentary['CanEdit'] == true,
          replies: replyIds.map((replyId) {
            final reply = getCommentary(replyId);
            final replyToId = asNullableInt(reply['ReplyId']);
            final replyTo = replyToId == null ? null : getCommentary(replyToId);
            return CommentReply(
              id: replyId,
              user: getUser(asInt(reply['UserId'])),
              content: asStringOrEmpty(reply['Content']),
              createdAt: asDate(reply['CreatedAt']),
              canEdit: reply['CanEdit'] == true,
              replyToUser: replyTo == null
                  ? null
                  : getUser(asInt(replyTo['UserId'])),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

class OnlineInfo {
  const OnlineInfo({
    required this.onlineUserCount,
    required this.maxOnline,
    required this.dayCount,
    required this.dayRegister,
  });

  final int onlineUserCount;
  final int maxOnline;
  final int dayCount;
  final int dayRegister;

  static OnlineInfo decode(Object? value) {
    final record = asRecord(value, '在线信息');
    return OnlineInfo(
      onlineUserCount: asInt(record['OnlineUserCount']),
      maxOnline: asInt(record['MaxOnline']),
      dayCount: asInt(record['DayCount']),
      dayRegister: asInt(record['DayRegister']),
    );
  }
}

class UserGrowth {
  const UserGrowth({
    required this.experience,
    required this.coin,
    required this.level,
    required this.growthLevel,
    required this.currentLevelExperience,
    required this.nextLevelExperience,
    required this.signInStreak,
    required this.signedToday,
  });

  final int experience;
  final int coin;
  final int level;
  final int growthLevel;
  final int currentLevelExperience;
  final int? nextLevelExperience;
  final int signInStreak;
  final bool signedToday;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.userName,
    required this.avatarUrl,
    required this.email,
    required this.inviteCode,
    required this.groupName,
    required this.unreadNotificationCount,
    required this.registeredAt,
    required this.growth,
  });

  final int id;
  final String userName;
  final String avatarUrl;
  final String email;
  final String inviteCode;
  final String groupName;
  final int unreadNotificationCount;
  final DateTime? registeredAt;
  final UserGrowth growth;

  static UserProfile decode(Object? value) {
    final record = asRecord(value, '用户资料响应');
    final role = asRecordOrNull(record['Role']) ?? const <String, dynamic>{};
    final growth =
        asRecordOrNull(record['Growth']) ?? const <String, dynamic>{};
    return UserProfile(
      id: asInt(record['Id']),
      userName: asStringOrEmpty(record['UserName']),
      avatarUrl: asStringOrEmpty(record['Avatar']),
      email: asStringOrEmpty(record['Email']),
      inviteCode: asStringOrEmpty(record['InviteCode']),
      groupName: asStringOrEmpty(role['Name']),
      unreadNotificationCount: asInt(record['UnreadNotificationCount'], 0),
      registeredAt: asNullableDate(record['RegisterAt']),
      growth: UserGrowth(
        experience: asInt(growth['Exp'], 0),
        coin: asInt(growth['Coin'], 0),
        level: asInt(growth['Level'], 0),
        growthLevel: asInt(growth['GrowthLevel'], 0),
        currentLevelExperience: asInt(growth['CurrentLevelExp'], 0),
        nextLevelExperience: asNullableInt(growth['NextLevelExp']),
        signInStreak: asInt(growth['SignStreak'], 0),
        signedToday: asBool(growth['TodaySigned'], false),
      ),
    );
  }
}

class DailyCheckInResult {
  const DailyCheckInResult({
    required this.reward,
    required this.streak,
    required this.experience,
    required this.level,
  });

  final int reward;
  final int streak;
  final int experience;
  final int level;

  static DailyCheckInResult decode(Object? value) {
    final record = asRecord(value, '签到响应');
    return DailyCheckInResult(
      reward: asInt(record['Reward']),
      streak: asInt(record['Streak']),
      experience: asInt(record['Exp']),
      level: asInt(record['Level']),
    );
  }
}

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
