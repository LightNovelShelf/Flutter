import '../decode.dart';

enum CommunityFeedOrder { reply, latest, hot, featured }

extension CommunityFeedOrderWire on CommunityFeedOrder {
  String get wire => name;
}

enum CommunityFeedScope { all, today, week }

extension CommunityFeedScopeWire on CommunityFeedScope {
  String get wire => name;
}

class CommunityListQuery {
  const CommunityListQuery({
    this.boardKey = 'all',
    this.subCategoryKey = '',
    this.order = CommunityFeedOrder.reply,
    this.scope = CommunityFeedScope.all,
    this.page = 1,
    this.size = 6,
  });

  final String boardKey;
  final String subCategoryKey;
  final CommunityFeedOrder order;
  final CommunityFeedScope scope;
  final int page;
  final int size;

  CommunityListQuery copyWith({
    String? boardKey,
    String? subCategoryKey,
    CommunityFeedOrder? order,
    CommunityFeedScope? scope,
    int? page,
    int? size,
  }) => CommunityListQuery(
    boardKey: boardKey ?? this.boardKey,
    subCategoryKey: subCategoryKey ?? this.subCategoryKey,
    order: order ?? this.order,
    scope: scope ?? this.scope,
    page: page ?? this.page,
    size: size ?? this.size,
  );

  Map<String, Object?> encode() => <String, Object?>{
    'BoardKey': boardKey,
    'SubCategoryKey': subCategoryKey,
    'Order': order.wire,
    'Scope': scope.wire,
    'Page': page < 1 ? 1 : page,
    'Size': size < 1 ? 1 : size,
  };
}

class CommunityCatalogSubCategory {
  const CommunityCatalogSubCategory({
    required this.id,
    required this.key,
    required this.label,
  });

  final int id;
  final String key;
  final String label;
}

class CommunityCatalogBoard {
  const CommunityCatalogBoard({
    required this.id,
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.subCategories,
  });

  final int id;
  final String key;
  final String title;
  final String description;
  final String icon;
  final List<CommunityCatalogSubCategory> subCategories;

  static CommunityCatalogBoard decode(Object? value) {
    final board = asRecord(value, '社区版块目录');
    return CommunityCatalogBoard(
      id: asInt(board['Id']),
      key: asString(board['Key']),
      title: asString(board['Title']),
      description: asStringOrEmpty(board['Description']),
      icon: asStringOrEmpty(board['Icon']),
      subCategories: decodeOptionalList(board['SubCategories'], '社区子分类目录', (
        item,
      ) {
        final subCategory = asRecord(item, '社区子分类');
        return CommunityCatalogSubCategory(
          id: asInt(subCategory['Id']),
          key: asString(subCategory['Key']),
          label: asString(subCategory['Label']),
        );
      }),
    );
  }
}

class CommunitySubCategorySummary {
  const CommunitySubCategorySummary({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;

  static CommunitySubCategorySummary decode(Object? value) {
    final subCategory = asRecord(value, '社区子分类');
    return CommunitySubCategorySummary(
      key: asString(subCategory['Key']),
      label: asString(subCategory['Label']),
      count: asCount(subCategory['Count']),
    );
  }
}

class CommunityPagination {
  const CommunityPagination({
    required this.page,
    required this.size,
    required this.total,
    required this.totalPages,
    required this.hasMore,
  });

  final int page;
  final int size;
  final int total;
  final int totalPages;
  final bool hasMore;

  static const CommunityPagination empty = CommunityPagination(
    page: 1,
    size: 0,
    total: 0,
    totalPages: 0,
    hasMore: false,
  );

  static CommunityPagination decode(Object? value) {
    final page = asRecordOrEmpty(value);
    return CommunityPagination(
      page: asInt(page['Page'], 1).clamp(1, 1 << 30),
      size: asCount(page['Size']),
      total: asCount(page['Total']),
      totalPages: asCount(page['TotalPages']),
      hasMore: asBool(page['HasMore'], false),
    );
  }
}

class CommunityBoardSummary {
  const CommunityBoardSummary({
    required this.id,
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.todayPosts,
    required this.heatLabel,
  });

  final int id;
  final String key;
  final String title;
  final String description;
  final String icon;
  final int todayPosts;
  final String heatLabel;

  static CommunityBoardSummary decode(Object? value) {
    final board = asRecord(value, '社区版块');
    return CommunityBoardSummary(
      id: asInt(board['Id']),
      key: asString(board['Key']),
      title: asString(board['Title']),
      description: asStringOrEmpty(board['Description']),
      icon: asStringOrEmpty(board['Icon']),
      todayPosts: asCount(board['TodayPosts']),
      heatLabel: asStringOrEmpty(board['HeatLabel']),
    );
  }
}

class CommunityFeedItem {
  const CommunityFeedItem({
    required this.id,
    required this.boardKey,
    required this.boardName,
    required this.subCategoryKey,
    required this.subCategoryLabel,
    required this.title,
    required this.excerpt,
    required this.authorName,
    required this.authorIsDeleted,
    required this.authorAvatar,
    required this.publishedAt,
    required this.replies,
    required this.views,
    required this.heat,
    required this.likes,
    required this.favorites,
    required this.tags,
    required this.featured,
    required this.pinned,
    required this.locked,
  });

  final int id;
  final String boardKey;
  final String boardName;
  final String? subCategoryKey;
  final String? subCategoryLabel;
  final String title;
  final String excerpt;
  final String authorName;
  final bool authorIsDeleted;
  final String authorAvatar;
  final DateTime? publishedAt;
  final int replies;
  final int views;
  final int heat;
  final int likes;
  final int favorites;
  final List<String> tags;
  final bool featured;
  final bool pinned;
  final bool locked;

  /// 复制并替换计数与锁定位，乐观互动只改这几项。
  CommunityFeedItem copyWith({
    int? replies,
    int? views,
    int? heat,
    int? likes,
    int? favorites,
    bool? locked,
  }) => CommunityFeedItem(
    id: id,
    boardKey: boardKey,
    boardName: boardName,
    subCategoryKey: subCategoryKey,
    subCategoryLabel: subCategoryLabel,
    title: title,
    excerpt: excerpt,
    authorName: authorName,
    authorIsDeleted: authorIsDeleted,
    authorAvatar: authorAvatar,
    publishedAt: publishedAt,
    replies: replies ?? this.replies,
    views: views ?? this.views,
    heat: heat ?? this.heat,
    likes: likes ?? this.likes,
    favorites: favorites ?? this.favorites,
    tags: tags,
    featured: featured,
    pinned: pinned,
    locked: locked ?? this.locked,
  );

  static CommunityFeedItem decode(Object? value) {
    final item = asRecord(value, '社区帖子');
    return CommunityFeedItem(
      id: asInt(item['Id']),
      boardKey: asString(item['BoardKey']),
      boardName: asStringOrEmpty(item['BoardName']),
      subCategoryKey: asNullableString(item['SubCategoryKey']),
      subCategoryLabel: asNullableString(item['SubCategoryLabel']),
      title: asString(item['Title']),
      excerpt: asStringOrEmpty(item['Excerpt']),
      authorName: asStringOrEmpty(item['AuthorName']),
      authorIsDeleted: asBool(item['AuthorIsDeleted'], false),
      authorAvatar: asStringOrEmpty(item['AuthorAvatar']),
      publishedAt: asNullableDate(item['PublishedAt']),
      replies: asCount(item['Replies']),
      views: asCount(item['Views']),
      heat: asCount(item['Heat']),
      likes: asCount(item['Likes']),
      favorites: asCount(item['Favorites']),
      tags: decodeStringList(item['Tags']),
      featured: asBool(item['Featured'], false),
      pinned: asBool(item['Pinned'], false),
      locked: asBool(item['Locked'], false),
    );
  }
}

class CommunityHotRankItem {
  const CommunityHotRankItem({
    required this.id,
    required this.title,
    required this.boardName,
    required this.heat,
    required this.publishedAt,
  });

  final int id;
  final String title;
  final String boardName;
  final int heat;
  final DateTime? publishedAt;

  static CommunityHotRankItem decode(Object? value) {
    final item = asRecord(value, '社区热帖');
    return CommunityHotRankItem(
      id: asInt(item['Id']),
      title: asString(item['Title']),
      boardName: asStringOrEmpty(item['BoardName']),
      heat: asCount(item['Heat']),
      publishedAt: asNullableDate(item['PublishedAt']),
    );
  }
}

class CommunityActiveUserItem {
  const CommunityActiveUserItem({
    required this.id,
    required this.name,
    required this.avatar,
    required this.badge,
    required this.score,
    required this.summary,
  });

  final int id;
  final String name;
  final String avatar;
  final String badge;
  final int score;
  final String summary;

  static CommunityActiveUserItem decode(Object? value) {
    final item = asRecord(value, '社区活跃用户');
    return CommunityActiveUserItem(
      id: asInt(item['Id']),
      name: asString(item['Name']),
      avatar: asStringOrEmpty(item['Avatar']),
      badge: asStringOrEmpty(item['Badge']),
      score: asCount(item['Score']),
      summary: asStringOrEmpty(item['Summary']),
    );
  }
}

class CommunityReplyTarget {
  const CommunityReplyTarget({
    required this.id,
    required this.authorName,
    required this.authorIsDeleted,
  });

  final int id;
  final String authorName;
  final bool authorIsDeleted;
}

class CommunityThreadReply {
  const CommunityThreadReply({
    required this.id,
    required this.authorName,
    required this.authorIsDeleted,
    required this.authorBadge,
    required this.authorAvatar,
    required this.publishedAt,
    required this.content,
    required this.likes,
    required this.liked,
    required this.replyTo,
    required this.childReplies,
    required this.childPage,
    required this.canDelete,
  });

  final int id;
  final String authorName;
  final bool authorIsDeleted;
  final String? authorBadge;
  final String authorAvatar;
  final DateTime? publishedAt;
  final String content;
  final int likes;
  final bool liked;
  final CommunityReplyTarget? replyTo;
  final List<CommunityThreadReply> childReplies;
  final CommunityPagination childPage;

  /// 服务端下发的删除权限（作者本人或有社区编辑权限）。
  final bool canDelete;

  CommunityThreadReply copyWith({
    int? likes,
    bool? liked,
    List<CommunityThreadReply>? childReplies,
    CommunityPagination? childPage,
    bool? canDelete,
  }) => CommunityThreadReply(
    id: id,
    authorName: authorName,
    authorIsDeleted: authorIsDeleted,
    authorBadge: authorBadge,
    authorAvatar: authorAvatar,
    publishedAt: publishedAt,
    content: content,
    likes: likes ?? this.likes,
    liked: liked ?? this.liked,
    replyTo: replyTo,
    childReplies: childReplies ?? this.childReplies,
    childPage: childPage ?? this.childPage,
    canDelete: canDelete ?? this.canDelete,
  );

  static CommunityThreadReply decode(Object? value) {
    final reply = asRecord(value, '社区回复');
    final replyTo = asRecordOrNull(reply['ReplyTo']);
    return CommunityThreadReply(
      id: asInt(reply['Id']),
      authorName: asStringOrEmpty(reply['AuthorName']),
      authorIsDeleted: asBool(reply['AuthorIsDeleted'], false),
      authorBadge: asNullableString(reply['AuthorBadge']),
      authorAvatar: asStringOrEmpty(reply['AuthorAvatar']),
      publishedAt: asNullableDate(reply['PublishedAt']),
      canDelete: asBool(reply['CanDelete'], false),
      content: asStringOrEmpty(reply['Content']),
      likes: asCount(reply['Likes']),
      liked: asBool(reply['Liked'], false),
      replyTo: replyTo == null
          ? null
          : CommunityReplyTarget(
              id: asInt(replyTo['Id']),
              authorName: asStringOrEmpty(replyTo['AuthorName']),
              authorIsDeleted: asBool(replyTo['AuthorIsDeleted'], false),
            ),
      childReplies: decodeOptionalList(
        reply['ChildReplies'],
        '社区子回复',
        CommunityThreadReply.decode,
      ),
      childPage: CommunityPagination.decode(reply['ChildPage']),
    );
  }
}

class CommunityThreadDetail {
  const CommunityThreadDetail({
    required this.item,
    required this.liked,
    required this.favorited,
    required this.canEdit,
    required this.bodyHtml,
    required this.repliesPage,
    required this.replyItems,
    required this.relatedThreads,
  });

  final CommunityFeedItem item;
  final bool liked;
  final bool favorited;
  final bool canEdit;
  final String bodyHtml;
  final CommunityPagination repliesPage;
  final List<CommunityThreadReply> replyItems;
  final List<CommunityFeedItem> relatedThreads;

  CommunityThreadDetail copyWith({
    bool? liked,
    bool? favorited,
    CommunityPagination? repliesPage,
    List<CommunityThreadReply>? replyItems,
  }) => CommunityThreadDetail(
    item: item,
    liked: liked ?? this.liked,
    favorited: favorited ?? this.favorited,
    canEdit: canEdit,
    bodyHtml: bodyHtml,
    repliesPage: repliesPage ?? this.repliesPage,
    replyItems: replyItems ?? this.replyItems,
    relatedThreads: relatedThreads,
  );

  static CommunityThreadDetail decodeRequired(Object? value) {
    final response = asRecord(value, '社区帖子详情响应');
    return CommunityThreadDetail(
      item: CommunityFeedItem.decode(response),
      liked: asBool(response['Liked'], false),
      favorited: asBool(response['Favorited'], false),
      canEdit: asBool(response['CanEdit'], false),
      bodyHtml: asStringOrEmpty(response['BodyHtml']),
      repliesPage: CommunityPagination.decode(response['RepliesPage']),
      replyItems: decodeOptionalList(
        response['ReplyItems'],
        '社区回复',
        CommunityThreadReply.decode,
      ),
      relatedThreads: decodeOptionalList(
        response['RelatedThreads'],
        '相关帖子',
        CommunityFeedItem.decode,
      ),
    );
  }

  static CommunityThreadDetail? decodeNullable(Object? value) {
    if (value == null) return null;
    final record = asRecordOrNull(value);
    if (record != null && record.isEmpty) return null;
    return decodeRequired(value);
  }
}

class CommunityHomePayload {
  const CommunityHomePayload({
    required this.title,
    required this.subtitle,
    required this.announcement,
    required this.announcementLink,
    required this.todayThreads,
    required this.onlineUserCount,
    required this.catalogBoards,
    required this.boards,
    required this.subCategories,
    required this.selectedSubCategoryKey,
    required this.feed,
    required this.feedPage,
    required this.hotThreads,
    required this.activeUsers,
  });

  final String title;
  final String subtitle;
  final String announcement;
  final String announcementLink;
  final int todayThreads;
  final int onlineUserCount;
  final List<CommunityCatalogBoard> catalogBoards;
  final List<CommunityBoardSummary> boards;
  final List<CommunitySubCategorySummary> subCategories;
  final String selectedSubCategoryKey;
  final List<CommunityFeedItem> feed;
  final CommunityPagination feedPage;
  final List<CommunityHotRankItem> hotThreads;
  final List<CommunityActiveUserItem> activeUsers;

  static CommunityHomePayload decode(Object? value) {
    final response = asRecord(value, '社区首页响应');
    return CommunityHomePayload(
      title: asStringOrEmpty(response['Title']),
      subtitle: asStringOrEmpty(response['Subtitle']),
      announcement: asStringOrEmpty(response['Announcement']),
      announcementLink: asStringOrEmpty(response['AnnouncementLink']),
      todayThreads: asCount(response['TodayThreads']),
      onlineUserCount: asCount(response['OnlineUserCount']),
      catalogBoards: decodeOptionalList(
        response['CatalogBoards'],
        '社区版块目录',
        CommunityCatalogBoard.decode,
      ),
      boards: decodeOptionalList(
        response['Boards'],
        '社区版块',
        CommunityBoardSummary.decode,
      ),
      subCategories: decodeOptionalList(
        response['SubCategories'],
        '社区子分类',
        CommunitySubCategorySummary.decode,
      ),
      selectedSubCategoryKey: asStringOrEmpty(
        response['SelectedSubCategoryKey'],
      ),
      feed: decodeOptionalList(
        response['Feed'],
        '社区帖子流',
        CommunityFeedItem.decode,
      ),
      feedPage: CommunityPagination.decode(response['FeedPage']),
      hotThreads: decodeOptionalList(
        response['HotThreads'],
        '社区热帖',
        CommunityHotRankItem.decode,
      ),
      activeUsers: decodeOptionalList(
        response['ActiveUsers'],
        '社区活跃用户',
        CommunityActiveUserItem.decode,
      ),
    );
  }
}

class CommunityFeedPayload {
  const CommunityFeedPayload({
    required this.subCategories,
    required this.selectedSubCategoryKey,
    required this.feed,
    required this.feedPage,
  });

  final List<CommunitySubCategorySummary> subCategories;
  final String selectedSubCategoryKey;
  final List<CommunityFeedItem> feed;
  final CommunityPagination feedPage;

  static CommunityFeedPayload decode(Object? value) {
    final response = asRecord(value, '社区帖子流响应');
    return CommunityFeedPayload(
      subCategories: decodeOptionalList(
        response['SubCategories'],
        '社区子分类',
        CommunitySubCategorySummary.decode,
      ),
      selectedSubCategoryKey: asStringOrEmpty(
        response['SelectedSubCategoryKey'],
      ),
      feed: decodeOptionalList(
        response['Feed'],
        '社区帖子流',
        CommunityFeedItem.decode,
      ),
      feedPage: CommunityPagination.decode(response['FeedPage']),
    );
  }
}

class CommunityReplyChildrenPayload {
  const CommunityReplyChildrenPayload({
    required this.items,
    required this.page,
  });

  final List<CommunityThreadReply> items;
  final CommunityPagination page;

  static CommunityReplyChildrenPayload decode(Object? value) {
    final response = asRecord(value, '社区子回复响应');
    return CommunityReplyChildrenPayload(
      items: decodeOptionalList(
        response['Items'],
        '社区子回复',
        CommunityThreadReply.decode,
      ),
      page: CommunityPagination.decode(response['Page']),
    );
  }
}

class CommunityMyReplyItem {
  const CommunityMyReplyItem({
    required this.id,
    required this.threadId,
    required this.threadTitle,
    required this.boardName,
    required this.content,
    required this.publishedAt,
    required this.likes,
    required this.replyToName,
  });

  final int id;
  final int threadId;
  final String threadTitle;
  final String boardName;
  final String content;
  final DateTime? publishedAt;
  final int likes;
  final String? replyToName;

  static CommunityMyReplyItem decode(Object? value) {
    final item = asRecord(value, '我的社区回复');
    return CommunityMyReplyItem(
      id: asInt(item['Id']),
      threadId: asInt(item['ThreadId']),
      threadTitle: asString(item['ThreadTitle']),
      boardName: asStringOrEmpty(item['BoardName']),
      content: asStringOrEmpty(item['Content']),
      publishedAt: asNullableDate(item['PublishedAt']),
      likes: asCount(item['Likes']),
      replyToName: asNullableString(item['ReplyToName']),
    );
  }
}

class CommunityMyOverview {
  const CommunityMyOverview({
    required this.authorName,
    required this.publishedThreads,
    required this.participatedReplies,
    required this.favoriteThreads,
  });

  final String authorName;
  final List<CommunityFeedItem> publishedThreads;
  final List<CommunityMyReplyItem> participatedReplies;
  final List<CommunityFeedItem> favoriteThreads;

  static CommunityMyOverview decode(Object? value) {
    final response = asRecord(value, '我的社区响应');
    return CommunityMyOverview(
      authorName: asStringOrEmpty(response['AuthorName']),
      publishedThreads: decodeOptionalList(
        response['PublishedThreads'],
        '我发布的帖子',
        CommunityFeedItem.decode,
      ),
      participatedReplies: decodeOptionalList(
        response['ParticipatedReplies'],
        '我参与的回复',
        CommunityMyReplyItem.decode,
      ),
      favoriteThreads: decodeOptionalList(
        response['FavoriteThreads'],
        '我收藏的帖子',
        CommunityFeedItem.decode,
      ),
    );
  }
}

class CommunityLikeToggleResult {
  const CommunityLikeToggleResult({required this.liked, required this.likes});

  final bool liked;
  final int likes;

  static CommunityLikeToggleResult decode(Object? value) {
    final result = asRecord(value, '点赞响应');
    return CommunityLikeToggleResult(
      liked: asBool(result['Liked']),
      likes: asCount(result['Likes']),
    );
  }
}

class CommunityFavoriteToggleResult {
  const CommunityFavoriteToggleResult({
    required this.favorited,
    required this.favorites,
  });

  final bool favorited;
  final int favorites;

  static CommunityFavoriteToggleResult decode(Object? value) {
    final result = asRecord(value, '收藏响应');
    return CommunityFavoriteToggleResult(
      favorited: asBool(result['Favorited']),
      favorites: asCount(result['Favorites']),
    );
  }
}
