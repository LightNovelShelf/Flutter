import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/features/community/community_thread_providers.dart';
import 'package:lightnovel/features/community/widgets/community_reply_row.dart';
import 'package:lightnovel/features/community/widgets/community_thread_header.dart';

const _emptyPage = CommunityPagination(
  page: 1,
  size: 0,
  total: 0,
  totalPages: 0,
  hasMore: false,
);

CommunityFeedItem _deletedThreadAuthor() => const CommunityFeedItem(
  id: 1,
  boardKey: 'general',
  boardName: '综合讨论',
  subCategoryKey: null,
  subCategoryLabel: null,
  title: '测试帖子',
  excerpt: '',
  authorId: 10,
  authorName: '楼主',
  authorIsDeleted: true,
  authorAvatar: '',
  publishedAt: null,
  replies: 0,
  views: 0,
  heat: 0,
  likes: 0,
  favorites: 0,
  tags: <String>[],
  featured: false,
  pinned: false,
  locked: false,
);

CommunityThreadReply _deletedReply() => const CommunityThreadReply(
  id: 2,
  authorId: 20,
  authorName: '回复者',
  authorIsDeleted: true,
  authorBadge: null,
  authorAvatar: '',
  publishedAt: null,
  content: '回复内容',
  likes: 0,
  liked: false,
  replyTo: CommunityReplyTarget(
    id: 3,
    authorName: '回复对象',
    authorIsDeleted: true,
  ),
  childReplies: <CommunityThreadReply>[],
  childPage: _emptyPage,
  canDelete: false,
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: SizedBox(width: 600, child: child)),
    ),
  ),
);

void main() {
  testWidgets('帖子详情显示已注销的楼主状态', (tester) async {
    final detail = CommunityThreadDetail(
      item: _deletedThreadAuthor(),
      liked: false,
      favorited: false,
      canEdit: false,
      content: '',
      repliesPage: _emptyPage,
      replyItems: const <CommunityThreadReply>[],
      relatedThreads: const <CommunityFeedItem>[],
    );

    await _pump(
      tester,
      CommunityThreadHeader(
        detail: detail,
        controller: CommunityThreadController((threadId: 1, focusReplyId: 0)),
        threadActionBusy: false,
        canReply: false,
        error: null,
        onReply: () async {},
      ),
    );

    expect(find.text('楼主（已注销）'), findsOneWidget);
  });

  testWidgets('回复作者和回复对象显示已注销状态', (tester) async {
    await _pump(
      tester,
      CommunityReplyRow(
        reply: _deletedReply(),
        isChild: false,
        highlighted: false,
        canReply: false,
        busy: false,
        onLike: () {},
        onReply: () {},
        onDelete: () {},
      ),
    );

    expect(find.text('回复者（已注销）'), findsOneWidget);
    expect(find.text('回复 回复对象（已注销）'), findsOneWidget);
  });
}
