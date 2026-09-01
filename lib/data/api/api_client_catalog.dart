import '../../core/network/request_scheduler.dart';
import 'api_client.dart';
import 'models.dart';

/// 书库/漫画：列表、搜索、详情、正文、批量取书。
extension ApiClientCatalog on ApiClient {
  Future<BookListPage> getLatestBookList({
    bool ignoreJapanese = false,
    bool ignoreAI = false,
    int? size,
  }) => invoke('GetLatestBookList', <String, Object?>{
    'IgnoreJapanese': ignoreJapanese,
    'IgnoreAI': ignoreAI,
    'Size': ?size,
  }, BookListPage.decode);

  Future<BookListPage> getBookList({
    required int page,
    required int size,
    required BookListOrder order,
    bool ignoreJapanese = false,
    bool ignoreAI = false,
  }) => invoke('GetBookList', <String, Object?>{
    'Page': page,
    'Size': size,
    'Order': order.wire,
    'IgnoreJapanese': ignoreJapanese,
    'IgnoreAI': ignoreAI,
  }, BookListPage.decode);

  /// 按系列分组列出小说；分组键由服务端分类器给出（中文名优先）。
  Future<NovelSeriesListPage> getNovelSeriesList({
    required int page,
    required int size,
    required BookListOrder order,
    bool ignoreJapanese = false,
    bool ignoreAI = false,
  }) => invoke('GetSeriesList', <String, Object?>{
    'Type': BookType.novel.wire,
    'Page': page,
    'Size': size,
    'Order': order.wire,
    'IgnoreJapanese': ignoreJapanese,
    'IgnoreAI': ignoreAI,
  }, NovelSeriesListPage.decode);

  /// 精确列出某个系列下的全部小说；系列名必须是 [getNovelSeriesList] 给出的分组键。
  Future<BookListPage> getBooksBySeries({
    required String seriesName,
    required int page,
    required int size,
    required BookListOrder order,
    bool ignoreJapanese = false,
    bool ignoreAI = false,
  }) => invoke('GetBooksBySeries', <String, Object?>{
    'Type': BookType.novel.wire,
    'SeriesName': seriesName,
    'Page': page,
    'Size': size,
    'Order': order.wire,
    'IgnoreJapanese': ignoreJapanese,
    'IgnoreAI': ignoreAI,
  }, BookListPage.decode);

  /// 周期是天数：1 日榜、7 周榜、31 月榜。
  Future<List<BookListItem>> getRank(int days) =>
      invoke('GetRank', <String, Object?>{'Days': days}, decodeBookListItems);

  Future<BookListPage> searchNovelBooks(
    BookSearchRequest request, {
    CancelToken? cancelToken,
  }) => invoke(
    _novelSearchMethod(request.mode),
    _encodeSearch(
      request,
      request.mode == BookSearchMode.exact
          ? '"${request.keywords}"'
          : request.keywords,
    ),
    BookListPage.decode,
    cancelToken: cancelToken,
  );

  Future<ComicSeriesListPage> searchComicSeries(
    BookSearchRequest request, {
    CancelToken? cancelToken,
  }) => invoke(
    'SearchComicSeries',
    <String, Object?>{
      ..._encodeSearch(request, request.keywords),
      'Mode': request.mode.name,
    },
    ComicSeriesListPage.decode,
    cancelToken: cancelToken,
  );

  Future<ComicSeriesListPage> getComicList({
    required int page,
    required ComicOrder order,
    int size = 24,
  }) => invoke('GetComicList', <String, Object?>{
    'Page': page,
    'Size': size,
    'Order': order.wire,
  }, ComicSeriesListPage.decode);

  Future<BookDetail> getBookInfo(int id) =>
      invoke('GetBookInfo', <String, Object?>{'Id': id}, BookDetail.decode);

  Future<NovelContent> getNovelContent({
    required int bookId,
    required int sortNum,
    String? convert,
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) => invoke(
    'GetNovelContent',
    <String, Object?>{'Bid': bookId, 'SortNum': sortNum, 'Convert': ?convert},
    NovelContent.decode,
    priority: priority,
    cancelToken: cancelToken,
  );

  Future<ComicInfo> getComicInfo(int id) =>
      invoke('GetComicInfo', <String, Object?>{'Id': id}, ComicInfo.decode);

  Future<ComicSeriesDetail> getComicSeriesInfo(
    String seriesTitle, {
    ComicOrder order = ComicOrder.latest,
  }) => invoke('GetComicSeriesInfo', <String, Object?>{
    'SeriesTitle': seriesTitle,
    'Order': order.wire,
  }, ComicSeriesDetail.decode);

  Future<ComicContent> getComicContent({
    required int chapterId,
    int skip = 0,
    int take = 6,
    RequestPriority priority = RequestPriority.interactive,
  }) => invoke(
    'GetComicContent',
    <String, Object?>{'Cid': chapterId, 'Skip': skip, 'Take': take},
    ComicContent.decode,
    priority: priority,
  );

  Future<void> saveReadPosition({
    required int bookId,
    required int chapterId,
    required String position,
  }) => invoke('SaveReadPosition', <String, Object?>{
    'Bid': bookId,
    'Cid': chapterId,
    'XPath': position,
  }, (_) {});

  Future<List<BookListItem>> getBookListByIds(List<int> ids) {
    final unique = ApiClient.normalizeBatchIds(ids);
    if (unique.isEmpty) {
      return Future<List<BookListItem>>.value(<BookListItem>[]);
    }
    return invoke('GetBookListByIds', <String, Object?>{
      'Ids': unique,
    }, decodeResolvableBookListItems);
  }

  /// 超过单次上限的 id 分片串行取回，并发发出只会被限流器排队。
  Future<List<BookListItem>> getBooksByIdsBatched(List<int> ids) async {
    if (ids.length <= ApiClient.batchIdLimit) return getBookListByIds(ids);
    final books = <BookListItem>[];
    for (var index = 0; index < ids.length; index += ApiClient.batchIdLimit) {
      final end = index + ApiClient.batchIdLimit;
      books.addAll(
        await getBookListByIds(
          ids.sublist(index, end < ids.length ? end : ids.length),
        ),
      );
    }
    return books;
  }

  Future<ComicSeriesListPage> getComicSeriesByIds(List<int> ids) {
    final unique = ApiClient.normalizeBatchIds(ids);
    if (unique.isEmpty) {
      return Future<ComicSeriesListPage>.value(
        const ComicSeriesListPage(
          page: 1,
          totalPages: 0,
          items: <ComicSeriesListItem>[],
        ),
      );
    }
    return invoke('GetBookListByIds', <String, Object?>{
      'Ids': unique,
      'Type': BookType.comic.wire,
    }, ComicSeriesListPage.decode);
  }
}

String _novelSearchMethod(BookSearchMode mode) => switch (mode) {
  BookSearchMode.fuzzy || BookSearchMode.exact => 'GetBookList',
  BookSearchMode.title => 'GetBookListByTitle',
  BookSearchMode.author => 'GetBookListByAuthor',
  BookSearchMode.name => 'GetBookListByName',
  BookSearchMode.tags => 'GetBookListByTags',
};

Map<String, Object?> _encodeSearch(
  BookSearchRequest request,
  String keywords,
) => <String, Object?>{
  'KeyWords': keywords,
  'Page': request.page,
  'Size': request.size,
  'IgnoreJapanese': request.ignoreJapanese,
  'IgnoreAI': request.ignoreAI,
};
