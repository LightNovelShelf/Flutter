import 'package:flutter/widgets.dart';

import '../data/api/models.dart';
import '../data/repositories/comment_thread_repository.dart';
import '../features/book/book_detail_screen.dart';
import '../features/book/comments_screen.dart';
import '../features/community/community_mine_screen.dart';
import '../features/community/community_notifications_screen.dart';
import '../features/community/community_rankings_screen.dart';
import '../features/community/community_thread_screen.dart';
import '../features/discover/announcement_detail_screen.dart';
import '../features/message/direct_chat_screen.dart';
import '../features/message/direct_message_list_screen.dart';
import '../features/settings/about_settings_screen.dart';
import '../features/settings/appearance_settings_screen.dart';
import '../features/settings/avatar_settings_screen.dart';
import '../features/settings/cache_settings_screen.dart';
import '../features/settings/content_settings_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/settings/reader_settings_screen.dart';
import '../features/shop/shop_screen.dart';

/// 能放进双栏右侧详情栏的页面。路由表也用它构建这些地址，两边解析规则一致。
///
/// 返回 null 表示这个地址只能整页打开。
Widget? buildPanePage(Uri uri) {
  final query = uri.queryParameters;
  int id(String raw) => int.tryParse(raw) ?? 0;
  return switch (uri.pathSegments) {
    ['book', final bookId] => BookDetailScreen(id: id(bookId)),
    ['book', final bookId, 'comments'] => CommentsScreen(
      target: CommentTarget.book(id(bookId)),
      title: query['title'] ?? '',
    ),
    ['announcement', final announcementId] => AnnouncementDetailScreen(
      id: id(announcementId),
    ),
    // 只带 replyId，服务端会定位它所在的主楼
    ['community', 'thread', final threadId] => CommunityThreadScreen(
      threadId: id(threadId),
      replyId: int.tryParse(query['replyId'] ?? ''),
    ),
    ['community', 'mine'] => const MyCommunityScreen(),
    ['community', 'notifications'] => const CommunityNotificationsScreen(),
    ['community', 'rankings'] => const CommunityRankingsScreen(),
    ['messages'] => const DirectMessageListScreen(),
    ['messages', final peerId] => DirectChatScreen(peerId: id(peerId)),
    ['shop'] => const ShopScreen(),
    ['settings', 'profile'] => const ProfileScreen(),
    ['settings', 'avatar'] => const AvatarSettingsScreen(),
    ['settings', 'appearance'] => const AppearanceSettingsScreen(),
    ['settings', 'content'] => const ContentSettingsScreen(),
    ['settings', 'reader', 'novel'] => const ReaderSettingsScreen(
      type: BookType.novel,
    ),
    ['settings', 'reader', 'comic'] => const ReaderSettingsScreen(
      type: BookType.comic,
    ),
    ['settings', 'cache'] => const CacheSettingsScreen(),
    ['settings', 'about'] => const AboutSettingsScreen(),
    _ => null,
  };
}
