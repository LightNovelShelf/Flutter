/// 线上枚举与请求参数对象：与传输层无关，单独放一处避免夹在客户端方法中间。
enum BookSearchMode { fuzzy, exact, title, author, name, tags }

enum BookListOrder { latest, newest, view }

extension BookListOrderWire on BookListOrder {
  String get wire => switch (this) {
    BookListOrder.latest => 'latest',
    BookListOrder.newest => 'new',
    BookListOrder.view => 'view',
  };
}

/// 路由参数回解：未知取值交给调用点决定默认排序。
BookListOrder? bookListOrderFromWire(String? value) => switch (value) {
  'latest' => BookListOrder.latest,
  'new' => BookListOrder.newest,
  'view' => BookListOrder.view,
  _ => null,
};

enum ComicOrder { latest, newest, view }

extension ComicOrderWire on ComicOrder {
  String get wire => switch (this) {
    ComicOrder.latest => 'latest',
    ComicOrder.newest => 'new',
    ComicOrder.view => 'view',
  };
}

class BookSearchRequest {
  const BookSearchRequest({
    required this.keywords,
    required this.mode,
    required this.page,
    required this.size,
    this.ignoreJapanese = false,
    this.ignoreAI = false,
  });

  final String keywords;
  final BookSearchMode mode;
  final int page;
  final int size;
  final bool ignoreJapanese;
  final bool ignoreAI;
}
