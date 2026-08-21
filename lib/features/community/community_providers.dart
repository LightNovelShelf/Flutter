import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../data/api/api_client.dart';
import '../../data/api/community_models.dart';
import '../../data/providers.dart';

const int communityPageSize = 6;

/// 「所有版面」伪版块的 key，服务端不返回时客户端补齐。
const String communityAllBoardKey = 'all';

/// 发帖须知的确认标记，只认一次。
const String communityPostNoticeKey = 'community_post_notice_accepted_v1';

final NumberFormat _compactNumber = NumberFormat.compact(locale: 'zh_CN');

/// 计数一律紧凑写法（1.2万），长数字会撑破卡片。
String formatCommunityCount(int value) => _compactNumber.format(value);

/// 社区相对时间：比 [formatRelativeTime] 粒度更细，且能显示未来时间。
String formatCommunityTime(DateTime? value) {
  if (value == null) return '';
  final delta = DateTime.now().difference(value);
  final abs = delta.abs();
  final suffix = delta.isNegative ? '后' : '前';
  if (abs.inMinutes < 1) return '刚刚';
  if (abs.inMinutes < 60) return '${abs.inMinutes} 分钟$suffix';
  if (abs.inHours < 24) return '${abs.inHours} 小时$suffix';
  if (abs.inDays < 26) return '${abs.inDays} 天$suffix';
  if (abs.inDays < 46) return '1 个月$suffix';
  if (abs.inDays < 320) return '${(abs.inDays / 30.4).round()} 个月$suffix';
  if (abs.inDays < 548) return '1 年$suffix';
  return '${(abs.inDays / 365.25).round()} 年$suffix';
}

/// 分页合并：保留既有顺序，只追加没见过的 id。服务端会重排热度，翻页必然撞重复。
List<T> mergeCommunityById<T>(
  List<T> existing,
  List<T> incoming,
  int Function(T item) idOf,
) {
  if (incoming.isEmpty) return existing;
  final seen = <int>{for (final T item in existing) idOf(item)};
  final merged = List<T>.of(existing);
  for (final T item in incoming) {
    if (seen.add(idOf(item))) merged.add(item);
  }
  return merged;
}

int communityFeedItemId(CommunityFeedItem item) => item.id;

int communityReplyId(CommunityThreadReply reply) => reply.id;

/// 服务端图标名 → Material 图标，未命中就拿版块标题的关键字猜。
IconData resolveCommunityBoardIcon(String icon, String title) {
  final normalized = icon
      .toLowerCase()
      .replaceFirst(RegExp(r'^mdi'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final mapped = switch (normalized) {
    'forum' || 'forumoutline' || 'commentmultiple' => Icons.forum_outlined,
    'messageoutline' => Icons.chat_bubble_outline,
    'bullhorn' || 'campaign' => Icons.campaign_outlined,
    'web' => Icons.language_outlined,
    'video' || 'playboxmultipleoutline' => Icons.videocam_outlined,
    'movie' => Icons.movie_outlined,
    'image' || 'imageoutline' => Icons.photo_outlined,
    'palette' => Icons.palette_outlined,
    'controller' ||
    'gamepadvariantoutline' ||
    'gamepadroundoutline' => Icons.sports_esports_outlined,
    'book' || 'bookopenvariant' => Icons.menu_book_outlined,
    'textboxoutline' => Icons.notes_outlined,
    'star' => Icons.star_outline,
    _ => null,
  };
  if (mapped != null) return mapped;
  if (title.contains('动画') || title.contains('番剧') || title.contains('视频')) {
    return Icons.videocam_outlined;
  }
  if (title.contains('漫画') || title.contains('插画') || title.contains('画')) {
    return Icons.photo_outlined;
  }
  if (title.contains('游戏')) return Icons.sports_esports_outlined;
  if (title.contains('小说') || title.contains('书')) {
    return Icons.menu_book_outlined;
  }
  if (title.contains('站务') || title.contains('公告') || title.contains('反馈')) {
    return Icons.campaign_outlined;
  }
  return Icons.forum_outlined;
}

/// 网络层错误直接透出服务端消息，其余归一成社区文案。
String describeCommunityError(Object error, {String fallback = '社区暂时不可用。'}) {
  if (error is ApiError) {
    return error.message.trim().isEmpty ? fallback : error.message;
  }
  return fallback;
}

/// 页面切换、筛选变更会主动取消在途请求。
bool isCommunityCancellation(Object error) =>
    error is RequestCancelledError ||
    (error is ApiError && error.cause is RequestCancelledError);

/// 服务端没有「所有版面」时补一个合成项，统计沿用首页的今日主题数。
List<CommunityBoardSummary> buildCommunityBoardOptions(
  CommunityHomePayload payload,
) {
  final boards = payload.boards;
  if (boards.any((board) => board.key == communityAllBoardKey)) return boards;
  return <CommunityBoardSummary>[
    CommunityBoardSummary(
      id: 0,
      key: communityAllBoardKey,
      title: '所有版面',
      description: '社区中的全部动态',
      icon: 'forum',
      todayPosts: payload.todayThreads,
      heatLabel: '',
    ),
    ...boards,
  ];
}

/// 最近一次成功的社区首页数据；排行榜页只读它，不再发请求。
class CommunityHomeCache extends Notifier<CommunityHomePayload?> {
  @override
  CommunityHomePayload? build() => null;

  void publish(CommunityHomePayload payload) => state = payload;
}

final NotifierProvider<CommunityHomeCache, CommunityHomePayload?>
communityHomeCacheProvider =
    NotifierProvider<CommunityHomeCache, CommunityHomePayload?>(
      CommunityHomeCache.new,
    );

@immutable
class CommunityHomeState {
  const CommunityHomeState({
    this.home,
    this.query = const CommunityListQuery(size: communityPageSize),
    this.feed = const <CommunityFeedItem>[],
    this.feedPage = CommunityPagination.empty,
    this.subCategories = const <CommunitySubCategorySummary>[],
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.categoriesLoading = false,
    this.error,
    this.loadMoreError,
  });

  final CommunityHomePayload? home;
  final CommunityListQuery query;
  final List<CommunityFeedItem> feed;
  final CommunityPagination feedPage;
  final List<CommunitySubCategorySummary> subCategories;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final bool categoriesLoading;
  final String? error;
  final String? loadMoreError;

  CommunityBoardSummary? get selectedBoard {
    final payload = home;
    if (payload == null || query.boardKey == communityAllBoardKey) return null;
    for (final CommunityBoardSummary board in payload.boards) {
      if (board.key == query.boardKey) return board;
    }
    return null;
  }

  static const Object _keep = Object();

  CommunityHomeState copyWith({
    Object? home = _keep,
    CommunityListQuery? query,
    List<CommunityFeedItem>? feed,
    CommunityPagination? feedPage,
    List<CommunitySubCategorySummary>? subCategories,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    bool? categoriesLoading,
    Object? error = _keep,
    Object? loadMoreError = _keep,
  }) => CommunityHomeState(
    home: identical(home, _keep) ? this.home : home as CommunityHomePayload?,
    query: query ?? this.query,
    feed: feed ?? this.feed,
    feedPage: feedPage ?? this.feedPage,
    subCategories: subCategories ?? this.subCategories,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    categoriesLoading: categoriesLoading ?? this.categoriesLoading,
    error: identical(error, _keep) ? this.error : error as String?,
    loadMoreError: identical(loadMoreError, _keep)
        ? this.loadMoreError
        : loadMoreError as String?,
  );
}

/// 首屏取整页数据，之后的筛选/翻页只取帖子流。
class CommunityHomeController extends Notifier<CommunityHomeState> {
  /// 筛选切换后骨架至少停这么久，命中缓存时不至于闪一下。
  static const Duration _minSkeleton = Duration(milliseconds: 300);

  int _generation = 0;
  CancelToken? _primary;
  CancelToken? _more;

  @override
  CommunityHomeState build() {
    ref.onDispose(() {
      _primary?.cancel();
      _more?.cancel();
    });
    return const CommunityHomeState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  /// 已有数据就不重复拉取，切回标签页不该刷掉当前筛选结果。
  Future<void> ensureLoaded() {
    if (state.home != null || state.loading) return Future<void>.value();
    return load();
  }

  Future<void> refresh() => load(refresh: true);

  Future<void> load({bool refresh = false}) async {
    final token = ++_generation;
    _primary?.cancel();
    _more?.cancel();
    final cancelToken = CancelToken();
    _primary = cancelToken;
    state = state.copyWith(
      loading: !refresh,
      refreshing: refresh,
      error: null,
      loadMoreError: null,
    );
    try {
      final payload = await _api.getCommunityHome(
        state.query.copyWith(page: 1, size: communityPageSize),
        cancelToken: cancelToken,
      );
      if (token != _generation) return;
      ref.read(communityHomeCacheProvider.notifier).publish(payload);
      state = state.copyWith(
        home: payload,
        feed: payload.feed,
        feedPage: payload.feedPage,
        subCategories: payload.subCategories,
        query: state.query.copyWith(
          subCategoryKey: payload.selectedSubCategoryKey,
        ),
        loading: false,
        refreshing: false,
        categoriesLoading: false,
        error: null,
      );
    } catch (error) {
      if (token != _generation || isCommunityCancellation(error)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: describeCommunityError(error),
      );
    }
  }

  Future<void> selectBoard(String boardKey) => _applyQuery(
    state.query.copyWith(boardKey: boardKey, subCategoryKey: ''),
    boardChanged: boardKey != state.query.boardKey,
  );

  Future<void> selectSubCategory(String subCategoryKey) =>
      _applyQuery(state.query.copyWith(subCategoryKey: subCategoryKey));

  Future<void> selectOrder(CommunityFeedOrder order) =>
      _applyQuery(state.query.copyWith(order: order));

  Future<void> selectScope(CommunityFeedScope scope) =>
      _applyQuery(state.query.copyWith(scope: scope));

  Future<void> _applyQuery(
    CommunityListQuery next, {
    bool boardChanged = false,
  }) async {
    if (_queryKey(next) == _queryKey(state.query)) return;
    if (state.home == null) {
      state = state.copyWith(query: next);
      return load();
    }
    final token = ++_generation;
    _primary?.cancel();
    _more?.cancel();
    final cancelToken = CancelToken();
    _primary = cancelToken;
    state = state.copyWith(
      query: next,
      feed: const <CommunityFeedItem>[],
      feedPage: CommunityPagination.empty,
      // 切版面立刻清空分类，`all` 直接收起分类行而不是留占位骨架。
      subCategories: boardChanged
          ? const <CommunitySubCategorySummary>[]
          : state.subCategories,
      categoriesLoading: boardChanged && next.boardKey != communityAllBoardKey,
      loading: true,
      error: null,
      loadMoreError: null,
    );
    final started = DateTime.now();
    try {
      final payload = await _api.getCommunityFeed(
        next.copyWith(page: 1, size: communityPageSize),
        cancelToken: cancelToken,
      );
      await _holdSkeleton(started);
      if (token != _generation) return;
      state = state.copyWith(
        feed: payload.feed,
        feedPage: payload.feedPage,
        subCategories: payload.subCategories,
        query: state.query.copyWith(
          subCategoryKey: payload.selectedSubCategoryKey,
        ),
        loading: false,
        categoriesLoading: false,
        error: null,
      );
    } catch (error) {
      if (token != _generation || isCommunityCancellation(error)) return;
      await _holdSkeleton(started);
      if (token != _generation) return;
      state = state.copyWith(
        loading: false,
        categoriesLoading: false,
        error: describeCommunityError(error),
      );
    }
  }

  Future<void> loadMore() async {
    final snapshot = state;
    if (snapshot.home == null ||
        snapshot.loading ||
        snapshot.refreshing ||
        snapshot.loadingMore ||
        !snapshot.feedPage.hasMore) {
      return;
    }
    final token = _generation;
    final cancelToken = CancelToken();
    _more = cancelToken;
    state = state.copyWith(loadingMore: true, loadMoreError: null);
    try {
      final size = snapshot.feedPage.size < 1
          ? communityPageSize
          : snapshot.feedPage.size;
      final payload = await _api.getCommunityFeed(
        snapshot.query.copyWith(page: snapshot.feedPage.page + 1, size: size),
        cancelToken: cancelToken,
      );
      if (token != _generation) return;
      state = state.copyWith(
        feed: mergeCommunityById(state.feed, payload.feed, communityFeedItemId),
        feedPage: payload.feedPage,
        loadingMore: false,
      );
    } catch (error) {
      if (token != _generation || isCommunityCancellation(error)) return;
      state = state.copyWith(
        loadingMore: false,
        loadMoreError: describeCommunityError(error, fallback: '无法加载更多讨论。'),
      );
    }
  }

  Future<void> _holdSkeleton(DateTime started) {
    final elapsed = DateTime.now().difference(started);
    if (elapsed >= _minSkeleton) return Future<void>.value();
    return Future<void>.delayed(_minSkeleton - elapsed);
  }

  String _queryKey(CommunityListQuery query) =>
      '${query.boardKey}:${query.subCategoryKey}:${query.order.wire}:${query.scope.wire}';
}

final NotifierProvider<CommunityHomeController, CommunityHomeState>
communityHomeProvider =
    NotifierProvider<CommunityHomeController, CommunityHomeState>(
      CommunityHomeController.new,
    );

class CommunityPostNoticeStore {
  const CommunityPostNoticeStore(this._ref);

  final Ref _ref;

  Future<bool> isAccepted() async {
    final value = await _ref
        .read(appRuntimeProvider)
        .keyValueStore
        .read(communityPostNoticeKey);
    return value == 'true';
  }

  Future<void> accept() => _ref
      .read(appRuntimeProvider)
      .keyValueStore
      .write(communityPostNoticeKey, 'true');
}

final Provider<CommunityPostNoticeStore> communityPostNoticeProvider =
    Provider<CommunityPostNoticeStore>(CommunityPostNoticeStore.new);
