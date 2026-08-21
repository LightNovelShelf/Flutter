import '../decode.dart';
import 'book.dart';
import 'read_position.dart';

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

  static List<ComicChapterSummary> decodeList(Object? value) =>
      decodeOptionalList(value, '漫画章节', (item) {
        final chapter = asRecord(item, '漫画章节');
        return ComicChapterSummary(
          id: asInt(chapter['Id']),
          sortNum: asInt(chapter['SortNum']),
          title: asString(chapter['Title']),
          createdAt: asDate(chapter['CreatedAt']),
          updatedAt: asNullableDate(chapter['UpdatedAt']),
          pageCount: asCount(chapter['PageCount']),
        );
      });
}

class ComicImage {
  const ComicImage({required this.url, required this.placeholder});

  final String url;
  final String placeholder;

  static ComicImage decode(Object? value) {
    final cover = decodeCover(value);
    return ComicImage(url: cover.url, placeholder: cover.placeholder ?? '');
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
    final cover = decodeCover(book['Cover']);
    return ComicInfo(
      id: asInt(book['Id']),
      coverUrl: cover.url,
      coverPlaceholder: cover.placeholder,
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
    final images = decodeOptionalList(
      chapter['Images'],
      '漫画分页',
      ComicImage.decode,
    );
    return ComicContent(
      chapter: ComicContentChapter(
        id: asInt(chapter['Id']),
        bookId: asInt(chapter['BookId']),
        bookName: asStringOrEmpty(chapter['BookName']),
        title: asString(chapter['Title']),
        sortNum: asInt(chapter['SortNum']),
        total: asCount(chapter['Total'], images.length),
        skip: asCount(chapter['Skip']),
        images: images,
      ),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }
}
