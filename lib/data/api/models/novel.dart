import '../decode.dart';
import 'read_position.dart';

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
        canEdit: asBool(chapter['CanEdit'], false),
      ),
      readPosition: BookReadPosition.decodeNullable(response['ReadPosition']),
    );
  }
}
