import '../decode.dart';

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
