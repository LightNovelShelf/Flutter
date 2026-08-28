import '../../core/network/request_scheduler.dart';
import 'api_client.dart';
import 'models.dart';

/// 社区板块：帖子、回复、点赞收藏、通知。
extension ApiClientCommunity on ApiClient {
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
    int focusReplyId = 0,
    bool? trackView,
    CancelToken? cancelToken,
  }) {
    final page = ApiClient.atLeastOne(replyPage);
    return invoke(
      'GetCommunityThread',
      <String, Object?>{
        'ThreadId': threadId,
        'ReplyPage': page,
        'ReplySize': ApiClient.atLeastOne(replySize),
        // 只有第一页计入浏览量，翻页不重复累加。
        'TrackView': trackView ?? page == 1,
        // 每页都带锚点：服务端把目标回复所在主楼置顶在第一页、后续页跳过它
        'FocusReplyId': focusReplyId,
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

  Future<void> deleteCommunityThread(int threadId) async {
    await invoke('DeleteCommunityThread', <String, Object?>{
      'ThreadId': threadId,
    }, (_) {});
  }

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

  Future<void> deleteCommunityReply(int replyId) async {
    await invoke('DeleteCommunityReply', <String, Object?>{
      'ReplyId': replyId,
    }, (_) {});
  }

  Future<CommunityReplyChildrenPayload> getCommunityReplyChildren({
    required int threadId,
    required int parentReplyId,
    int page = 1,
    int size = 3,
    int afterReplyId = 0,
    CancelToken? cancelToken,
  }) => invoke(
    'GetCommunityReplyChildren',
    <String, Object?>{
      'ThreadId': threadId,
      'ParentReplyId': parentReplyId,
      'Page': ApiClient.atLeastOne(page),
      'Size': ApiClient.atLeastOne(size),
      'AfterReplyId': afterReplyId < 0 ? 0 : afterReplyId,
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
    <String, Object?>{
      'Page': ApiClient.atLeastOne(page),
      'Size': ApiClient.atLeastOne(size),
    },
    AppNotificationPage.decode,
    cancelToken: cancelToken,
  );

  Future<void> markNotifications(List<int> ids) async {
    if (ids.isEmpty) return;
    await invoke('MarkNotifications', <String, Object?>{'Ids': ids}, (_) {});
  }
}
