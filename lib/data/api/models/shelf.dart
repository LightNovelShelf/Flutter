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

/// 书架条目类型，写回服务端时用大写字面量。
enum ShelfItemType { novel, comic, folder }

extension ShelfItemTypeWire on ShelfItemType {
  String get wire => switch (this) {
    ShelfItemType.novel => 'NOVEL',
    ShelfItemType.comic => 'COMIC',
    ShelfItemType.folder => 'FOLDER',
  };
}

/// 书架里的一本书。小说与漫画共用书籍 ID 空间，但按类型分别记账。
typedef ShelfBookRef = ({int id, ShelfItemType type});

/// 书架条目：小说、漫画或文件夹。
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
    required this.type,
    required int id,
    required this.index,
    required this.parents,
    required this.updatedAt,
  }) : assert(type != ShelfItemType.folder, '书籍条目只能是小说或漫画。'),
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

  bool get isBook => type != ShelfItemType.folder;

  bool get isComic => type == ShelfItemType.comic;

  /// 小说与漫画的 ID 取自同一个空间，带类型前缀才能唯一标识一个条目。
  String get key => '${type.wire}:${isBook ? bookId : folderId}';

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
    if (value == 'NOVEL' || value == 'Novel') return ShelfItemType.novel;
    if (value == 'COMIC' || value == 'Comic') return ShelfItemType.comic;
    if (value == 'FOLDER' || value == 'Folder') return ShelfItemType.folder;
    throw const ApiError('服务端返回了无效的书架条目类型。', ApiErrorCategory.server);
  }

  static ShelfItem decode(Object? value) {
    final item = asRecord(value, '书架条目');
    final type = _decodeType(item['type'] ?? item['Type']);
    final index = asInt(item['index'] ?? item['Index'], 0);
    final parents = decodeStringList(item['parents'] ?? item['Parents']);
    final updatedAt = asStringOrEmpty(item['updateAt'] ?? item['UpdateAt']);
    final rawId = item['id'] ?? item['Id'];

    if (type != ShelfItemType.folder) {
      return ShelfItem.book(
        type: type,
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
    'type': type.wire,
    'updateAt': updatedAt,
  };
}

class UserShelf {
  const UserShelf({required this.items});

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
    return UserShelf(items: rawItems.map(ShelfItem.decode).toList());
  }
}
