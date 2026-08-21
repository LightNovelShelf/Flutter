import '../../../core/network/api_error.dart';
import '../decode.dart';

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
    final record = asRecordOrEmpty(value);
    // 老接口直接回数组，新接口包一层 `{data, ver}`，两种大小写都出现过。
    // 从未保存过书架的账号返回空对象 `{}`，按空书架处理。
    final rawItems = value is List
        ? value
        : decodeOptionalList<Object?>(
            record['data'] ?? record['Data'],
            '书架响应',
            (item) => item,
          );
    final rawVersion = record['ver'] ?? record['Ver'];
    return UserShelf(
      version: rawVersion is String || rawVersion is num ? '$rawVersion' : null,
      items: rawItems.map(ShelfItem.decode).toList(),
    );
  }
}
