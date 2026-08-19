import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../core/network/signalr_connection.dart';
import 'community_models.dart';
import 'decode.dart';
import 'endpoints.dart';
import 'models.dart';

/// 401 时调用去刷新令牌；返回 false 表示刷不动了。
typedef AuthRetryHandler = Future<bool> Function();

class SessionTokens {
  const SessionTokens({required this.sessionToken, required this.refreshToken});

  final String sessionToken;
  final String refreshToken;

  static SessionTokens decode(Object? value) {
    final envelope = asRecord(value, '登录响应');
    _throwIfFailed(envelope, '登录失败。');
    final response =
        asRecordOrNull(envelope['Response'] ?? envelope['response']) ??
        envelope;
    return SessionTokens(
      sessionToken: asString(response['Token'] ?? response['token']),
      refreshToken: asString(
        response['RefreshToken'] ?? response['refreshToken'],
      ),
    );
  }
}

void _throwIfFailed(Map<String, dynamic> envelope, String fallbackMessage) {
  final success = envelope['Success'] ?? envelope['success'];
  if (success != false) return;
  final status = envelope['Status'] ?? envelope['status'];
  final message = envelope['Msg'] ?? envelope['msg'];
  final statusCode = status is num ? status.toInt() : null;
  throw ApiError(
    message is String && message.isNotEmpty ? message : fallbackMessage,
    statusCode == 401 || statusCode == -100
        ? ApiErrorCategory.auth
        : ApiErrorCategory.server,
    status: statusCode,
  );
}

/// 解开 SignalR 响应信封 `{success, status, msg, response}`，取出业务数据。
Object? unwrapSignalRResponse(Object? value) {
  final envelope = asRecordOrNull(value);
  if (envelope == null) {
    throw const ApiError('服务端返回了无效的响应。', ApiErrorCategory.server);
  }
  final success = envelope['Success'] ?? envelope['success'];
  if (success is! bool) {
    throw const ApiError('服务端返回了无效的响应。', ApiErrorCategory.server);
  }
  _throwIfFailed(envelope, '请求失败。');
  return _decompress(envelope['Response'] ?? envelope['response']);
}

Object? _decompress(Object? value) {
  if (value is! String) return value;
  // 服务端 `UseGzip` 后 byte[] 在 JSON 协议下是 base64 文本；普通字符串原样返回。
  late final List<int> bytes;
  try {
    bytes = base64Decode(value);
  } catch (_) {
    return value;
  }
  if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return value;
  try {
    return jsonDecode(utf8.decode(gzip.decode(bytes)));
  } catch (error) {
    throw ApiError('服务端返回了无效的压缩响应。', ApiErrorCategory.server, cause: error);
  }
}

enum BookSearchMode { fuzzy, exact, title, author, name, tags }

enum BookListOrder { latest, newest, view }

extension BookListOrderWire on BookListOrder {
  String get wire => switch (this) {
    BookListOrder.latest => 'latest',
    BookListOrder.newest => 'new',
    BookListOrder.view => 'view',
  };
}

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

class ApiClient {
  ApiClient({
    required SignalRConnection signalR,
    required RateLimitRequestScheduler scheduler,
    required Future<Map<String, String>> Function() headers,
    this.authRetry,
  }) : _signalR = signalR,
       _scheduler = scheduler,
       _headers = headers;

  final SignalRConnection _signalR;
  final RateLimitRequestScheduler _scheduler;
  final Future<Map<String, String>> Function() _headers;
  AuthRetryHandler? authRetry;

  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    for (var hasRetried = false; ; hasRetried = true) {
      if (cancelToken?.isCancelled ?? false) {
        throw const RequestCancelledError();
      }
      Object? envelope;
      try {
        envelope = await _scheduler.add(
          () => _signalR.invoke(methodName, <Object?>[
            params,
            <String, Object?>{'UseGzip': true},
          ]),
          priority: priority,
          cancelToken: cancelToken,
        );
      } catch (error) {
        if (error is RequestCancelledError ||
            (cancelToken?.isCancelled ?? false)) {
          throw const RequestCancelledError();
        }
        final apiError = toApiError(error);
        if (!apiError.isAuth || hasRetried || authRetry == null) throw apiError;
        // 会话令牌只在建连时校验，刷新后必须重连才带得上新令牌。
        if (!await authRetry!()) throw apiError;
        await _signalR.reset();
        continue;
      }
      return decode(unwrapSignalRResponse(envelope));
    }
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('${ServiceEndpoints.apiOrigin}$path')
        .replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...await _headers(),
    };
    return _scheduler.add(() async {
      final client = http.Client();
      try {
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) request.body = jsonEncode(body);
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        return await http.Response.fromStream(streamed);
      } finally {
        client.close();
      }
    });
  }

  Object? _decodeHttpBody(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

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

  /// 周期是天数：1 日榜、7 周榜、31 月榜。
  Future<List<BookListItem>> getRank(int days) =>
      invoke('GetRank', <String, Object?>{'Days': days}, decodeBookListItems);

  static String _novelSearchMethod(BookSearchMode mode) => switch (mode) {
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

  Future<OnlineInfo> getOnlineInfo() =>
      invoke('GetOnlineInfo', null, OnlineInfo.decode);

  Future<AnnouncementPage> getAnnouncementList({
    int page = 1,
    int size = 5,
    CancelToken? cancelToken,
  }) => invoke(
    'GetAnnouncementList',
    <String, Object?>{'Page': page, 'Size': size},
    AnnouncementPage.decode,
    cancelToken: cancelToken,
  );

  Future<AnnouncementItem> getAnnouncementDetail(int id) => invoke(
    'GetAnnouncementDetail',
    <String, Object?>{'Id': id},
    AnnouncementItem.decode,
  );

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
    int take = 12,
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

  Future<CommentPage> getComments({
    required CommentTargetType type,
    required int id,
    required int page,
    int size = 10,
    String? seriesTitle,
  }) => invoke('GetComments', <String, Object?>{
    'Type': type.wire,
    'Id': id,
    'Page': page,
    'Size': size,
    'SeriesTitle': ?seriesTitle,
  }, CommentPage.decode);

  Map<String, Object?> _encodeComment({
    required CommentTargetType type,
    required int id,
    required String content,
    String? seriesTitle,
    int? parentId,
    int? replyId,
  }) => <String, Object?>{
    'Type': type.wire,
    'Id': id,
    'Content': content,
    'SeriesTitle': ?seriesTitle,
    'ParentId': ?parentId,
    'ReplyId': ?replyId,
  };

  Future<void> postComment({
    required CommentTargetType type,
    required int id,
    required String content,
    String? seriesTitle,
  }) => invoke(
    'PostComment',
    _encodeComment(
      type: type,
      id: id,
      content: content,
      seriesTitle: seriesTitle,
    ),
    (_) {},
  );

  Future<void> replyComment({
    required CommentTargetType type,
    required int id,
    required String content,
    String? seriesTitle,
    int? parentId,
    int? replyId,
  }) => invoke(
    'ReplyComment',
    _encodeComment(
      type: type,
      id: id,
      content: content,
      seriesTitle: seriesTitle,
      parentId: parentId,
      replyId: replyId,
    ),
    (_) {},
  );

  Future<void> deleteComment(int id) =>
      invoke('DeleteComment', <String, Object?>{'Id': id}, (_) {});

  Future<CommunityHomePayload> getCommunityHome(
    CommunityListQuery query, {
    CancelToken? cancelToken,
  }) => invoke(
    'GetCommunityHome',
    query.encode(),
    CommunityHomePayload.decode,
    cancelToken: cancelToken,
  );

  Future<CommunityFeedPayload> getCommunityFeed(
    CommunityListQuery query, {
    CancelToken? cancelToken,
  }) => invoke(
    'GetCommunityFeed',
    query.encode(),
    CommunityFeedPayload.decode,
    cancelToken: cancelToken,
  );

  Future<CommunityThreadDetail?> getCommunityThread({
    required int threadId,
    int replyPage = 1,
    int replySize = 5,
    bool? trackView,
    CancelToken? cancelToken,
  }) {
    final page = replyPage < 1 ? 1 : replyPage;
    return invoke(
      'GetCommunityThread',
      <String, Object?>{
        'ThreadId': threadId,
        'ReplyPage': page,
        'ReplySize': replySize < 1 ? 1 : replySize,
        'TrackView': trackView ?? page == 1,
      },
      CommunityThreadDetail.decodeNullable,
      cancelToken: cancelToken,
    );
  }

  Future<CommunityThreadDetail> createCommunityThread({
    required String boardKey,
    String subCategoryKey = '',
    required String title,
    required String contentHtml,
  }) => invoke('CreateCommunityThread', <String, Object?>{
    'BoardKey': boardKey,
    'SubCategoryKey': subCategoryKey,
    'Title': title,
    'ContentHtml': contentHtml,
  }, CommunityThreadDetail.decodeRequired);

  Future<CommunityThreadReply> createCommunityReply({
    required int threadId,
    required String content,
    int? replyToId,
  }) => invoke('CreateCommunityReply', <String, Object?>{
    'ThreadId': threadId,
    'Content': content,
    'ReplyToId': ?replyToId,
  }, CommunityThreadReply.decode);

  Future<CommunityLikeToggleResult> toggleCommunityThreadLike(int threadId) =>
      invoke('ToggleCommunityThreadLike', <String, Object?>{
        'ThreadId': threadId,
      }, CommunityLikeToggleResult.decode);

  Future<CommunityFavoriteToggleResult> toggleCommunityThreadFavorite(
    int threadId,
  ) => invoke('ToggleCommunityThreadFavorite', <String, Object?>{
    'ThreadId': threadId,
  }, CommunityFavoriteToggleResult.decode);

  Future<CommunityLikeToggleResult> toggleCommunityReplyLike(int replyId) =>
      invoke('ToggleCommunityReplyLike', <String, Object?>{
        'ReplyId': replyId,
      }, CommunityLikeToggleResult.decode);

  Future<CommunityReplyChildrenPayload> getCommunityReplyChildren({
    required int threadId,
    required int parentReplyId,
    int page = 1,
    int size = 3,
    CancelToken? cancelToken,
  }) => invoke(
    'GetCommunityReplyChildren',
    <String, Object?>{
      'ThreadId': threadId,
      'ParentReplyId': parentReplyId,
      'Page': page < 1 ? 1 : page,
      'Size': size < 1 ? 1 : size,
    },
    CommunityReplyChildrenPayload.decode,
    cancelToken: cancelToken,
  );

  Future<CommunityMyOverview> getMyCommunityOverview({
    CancelToken? cancelToken,
  }) => invoke(
    'GetMyCommunityOverview',
    <String, Object?>{},
    CommunityMyOverview.decode,
    cancelToken: cancelToken,
  );

  Future<AppNotificationPage> getNotifications({
    int page = 1,
    int size = 20,
    CancelToken? cancelToken,
  }) => invoke(
    'GetNotifications',
    <String, Object?>{'Page': page < 1 ? 1 : page, 'Size': size < 1 ? 1 : size},
    AppNotificationPage.decode,
    cancelToken: cancelToken,
  );

  Future<void> markNotifications(List<int> ids) async {
    if (ids.isEmpty) return;
    await invoke('MarkNotifications', <String, Object?>{'Ids': ids}, (_) {});
  }

  Future<ReadHistory> getReadHistory() =>
      invoke('GetReadHistory', null, ReadHistory.decode);

  Future<void> clearReadHistory() => invoke('ClearReadHistory', null, (_) {});

  Future<UserShelf> getBookShelf() =>
      invoke('GetBookShelf', null, UserShelf.decode);

  Future<void> saveBookShelf(UserShelf shelf) =>
      invoke('SaveBookShelf', <String, Object?>{
        'data': shelf.items.map((item) => item.encode()).toList(),
        'ver': shelf.version ?? shelfStructVersion,
      }, (_) {});

  static List<int> _normalizeBatchIds(List<int> ids) {
    final unique = ids.toSet().toList();
    if (unique.length > 24) {
      throw ArgumentError('单次批量请求最多 24 本书。');
    }
    return unique;
  }

  Future<List<BookListItem>> getBookListByIds(List<int> ids) {
    final unique = _normalizeBatchIds(ids);
    if (unique.isEmpty) {
      return Future<List<BookListItem>>.value(<BookListItem>[]);
    }
    return invoke('GetBookListByIds', <String, Object?>{
      'Ids': unique,
    }, decodeResolvableBookListItems);
  }

  Future<ComicSeriesListPage> getComicSeriesByIds(List<int> ids) {
    final unique = _normalizeBatchIds(ids);
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

  Future<UserProfile> getMyProfile() =>
      invoke('GetMyInfo', <String, Object?>{}, UserProfile.decode);

  Future<void> setAvatar(String url) =>
      invoke('SetAvatar', <String, Object?>{'Url': url}, (_) {});

  Future<DailyCheckInResult> checkIn() =>
      invoke('SignIn', <String, Object?>{}, DailyCheckInResult.decode);

  Future<SessionTokens> login({
    required String email,
    required String passwordHash,
  }) async {
    final response = await _request(
      'POST',
      ServiceEndpoints.loginPath,
      body: <String, Object?>{'email': email, 'password': passwordHash},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        '无法登录。',
        response.statusCode == 401
            ? ApiErrorCategory.auth
            : ApiErrorCategory.server,
        status: response.statusCode,
      );
    }
    return SessionTokens.decode(_decodeHttpBody(response));
  }

  Future<SessionTokens> register({
    required String userName,
    required String email,
    required String passwordHash,
    required String code,
    required String inviteCode,
  }) async {
    final response = await _request(
      'POST',
      ServiceEndpoints.registerPath,
      body: <String, Object?>{
        'userName': userName,
        'email': email,
        'password': passwordHash,
        'code': code,
        'inviteCode': inviteCode,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        '无法创建账号。',
        response.statusCode == 401
            ? ApiErrorCategory.auth
            : ApiErrorCategory.server,
        status: response.statusCode,
      );
    }
    return SessionTokens.decode(_decodeHttpBody(response));
  }

  Future<void> sendRegisterEmail(String email) =>
      _requestEmailCode(ServiceEndpoints.sendRegisterEmailPath, email);

  Future<void> sendResetEmail(String email) =>
      _requestEmailCode(ServiceEndpoints.sendResetEmailPath, email);

  Future<void> _requestEmailCode(String path, String email) async {
    final response = await _request(
      'GET',
      path,
      query: <String, String>{'email': email},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        '无法发送验证码。',
        ApiErrorCategory.server,
        status: response.statusCode,
      );
    }
    final body = asRecordOrNull(_decodeHttpBody(response));
    if (body != null) _throwIfFailed(body, '无法发送验证码。');
  }

  Future<void> resetPassword({
    required String email,
    required String newPasswordHash,
    required String code,
  }) async {
    final response = await _request(
      'POST',
      ServiceEndpoints.resetPasswordPath,
      body: <String, Object?>{
        'email': email,
        'newPassword': newPasswordHash,
        'code': code,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        '无法重置密码。',
        response.statusCode == 401
            ? ApiErrorCategory.auth
            : ApiErrorCategory.server,
        status: response.statusCode,
      );
    }
    final body = asRecordOrNull(_decodeHttpBody(response));
    if (body != null) _throwIfFailed(body, '无法重置密码。');
  }

  Future<String> refreshToken(String refreshToken) async {
    if (refreshToken.isEmpty) {
      throw const ApiError('需要登录后才能继续。', ApiErrorCategory.auth, status: 401);
    }
    final response = await _request(
      'POST',
      ServiceEndpoints.refreshTokenPath,
      body: <String, Object?>{'token': refreshToken},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        '登录状态已过期，请重新登录。',
        response.statusCode == 401 || response.statusCode == 404
            ? ApiErrorCategory.auth
            : ApiErrorCategory.server,
        status: response.statusCode,
      );
    }
    final envelope = asRecord(_decodeHttpBody(response), '刷新令牌响应');
    _throwIfFailed(envelope, '登录状态已过期，请重新登录。');
    return asString(
      envelope['Response'] ?? envelope['response'] ?? envelope['Token'],
    );
  }
}
