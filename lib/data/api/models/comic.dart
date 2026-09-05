import '../decode.dart';
import 'read_position.dart';

class ComicImage {
  const ComicImage({
    required this.url,
    required this.placeholder,
    required this.aspect,
  });

  final String url;
  final String placeholder;

  /// 整页高宽比，地址上没带 `size` 时为 null，由调用方按未知尺寸兜底。
  final double? aspect;

  static ComicImage decode(Object? value) {
    final cover = decodeCover(value);
    final size = extractImageSize(cover.url);
    return ComicImage(
      url: cover.url,
      placeholder: cover.placeholder ?? '',
      aspect: size == null ? null : size.height / size.width,
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
