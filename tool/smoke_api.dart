// 数据层冒烟测试：用真实服务端验证 SignalR 连接、请求编码与响应解码。
//
//   dart run tool/smoke_api.dart <refresh_token>
//
// 指向本地起的服务端（枚举名参数需要服务端已挂 JsonStringEnumConverter）：
//
//   dart run -DAPI_ORIGIN=http://127.0.0.1:5199 tool/smoke_api.dart <refresh_token>
//
import 'dart:io';

import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/core/network/request_scheduler.dart';
import 'package:lightnovel/core/network/signalr_connection.dart';
import 'package:lightnovel/data/api/api_client.dart';
import 'package:lightnovel/data/api/community_models.dart';
import 'package:lightnovel/data/api/endpoints.dart';
import 'package:lightnovel/data/api/models.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/smoke_api.dart <refresh_token>');
    exitCode = 64;
    return;
  }

  var sessionToken = '';
  final signalR = SignalRConnection(
    endpoint: ServiceEndpoints.signalRHub,
    accessTokenFactory: () async => sessionToken,
    headersFactory: () async => <String, String>{
      'User-Agent': 'LightNovelShelf/1.0.0',
    },
  );
  final api = ApiClient(
    signalR: signalR,
    scheduler: RateLimitRequestScheduler(),
    headers: () async => <String, String>{
      'User-Agent': 'LightNovelShelf/1.0.0',
      if (sessionToken.isNotEmpty) 'Authorization': 'Bearer $sessionToken',
    },
  );

  var failures = 0;
  Future<void> check(String name, Future<void> Function() body) async {
    try {
      await body();
      stdout.writeln('✓ $name');
    } catch (error) {
      failures += 1;
      stdout.writeln('✗ $name → $error');
    }
  }

  await check('refreshToken', () async {
    sessionToken = await api.refreshToken(args.first);
    if (sessionToken.isEmpty) throw StateError('空会话令牌');
  });

  await check('getOnlineInfo', () async {
    final info = await api.getOnlineInfo();
    stdout.writeln('   在线 ${info.onlineUserCount} / 峰值 ${info.maxOnline}');
  });

  await check('getLatestBookList', () async {
    final page = await api.getLatestBookList(size: 6);
    if (page.items.isEmpty) throw StateError('空列表');
    final book = page.items.first;
    stdout.writeln('   ${book.title} · 占位符=${book.coverPlaceholder ?? '无'}');
  });

  await check('getBookList(latest)', () async {
    final page = await api.getBookList(
      page: 1,
      size: 6,
      order: BookListOrder.latest,
    );
    stdout.writeln('   ${page.items.length} 本 / 共 ${page.totalPages} 页');
  });

  await check('getNovelSeriesList(latest)', () async {
    final page = await api.getNovelSeriesList(
      page: 1,
      size: 6,
      order: BookListOrder.latest,
    );
    if (page.items.isEmpty) throw StateError('空系列列表');
    final series = page.items.first;
    stdout.writeln(
      '   ${page.items.length} 个系列 / 共 ${page.totalPages} 页 · ${series.name} (${series.bookCount} 本)',
    );

    final books = await api.getBooksBySeries(
      seriesName: series.name,
      page: 1,
      size: 6,
      order: BookListOrder.latest,
    );
    if (books.items.isEmpty) throw StateError('系列内没有书籍');
    stdout.writeln('   getBooksBySeries → ${books.items.first.title}');
  });

  await check('getRank(7)', () async {
    final items = await api.getRank(7);
    stdout.writeln('   榜首 ${items.first.title}');
  });

  var comicId = 0;
  var comicTitle = '';
  var comicChapterId = 0;

  await check('getComicList', () async {
    final page = await api.getComicList(
      page: 1,
      order: ComicOrder.latest,
      size: 6,
    );
    if (page.items.isEmpty) throw StateError('空漫画列表');
    comicId = page.items.first.id;
    comicTitle = page.items.first.title;
    stdout.writeln('   ${page.items.length} 部漫画 · $comicTitle');
  });

  await check('searchComicSeries', () async {
    final page = await api.searchComicSeries(
      BookSearchRequest(
        keywords: comicTitle,
        mode: BookSearchMode.exact,
        page: 1,
        size: 6,
      ),
    );
    if (page.items.isEmpty) throw StateError('漫画系列搜索无结果');
    stdout.writeln('   ${page.items.length} 个系列');
  });

  await check('getComicSeriesInfo', () async {
    final series = await api.getComicSeriesInfo(comicTitle);
    if (series.volumes.isEmpty) throw StateError('漫画系列没有分卷');
    stdout.writeln('   ${series.title} · ${series.volumes.length} 卷');
  });

  await check('getAnnouncementList', () async {
    final page = await api.getAnnouncementList(page: 1, size: 3);
    stdout.writeln('   ${page.items.first.title}');
  });

  var bookId = 0;
  await check('getBookInfo', () async {
    final page = await api.getLatestBookList(size: 1);
    bookId = page.items.first.id;
    final detail = await api.getBookInfo(bookId);
    stdout.writeln('   ${detail.title} · ${detail.chapters.length} 章');
  });

  await check('getNovelContent', () async {
    final content = await api.getNovelContent(bookId: bookId, sortNum: 1);
    stdout.writeln(
      '   ${content.chapter.title} · ${content.chapter.content.length} 字节 · 字体=${content.chapter.fontUrl ?? '无'}',
    );
  });

  await check('getComicInfo', () async {
    final info = await api.getComicInfo(comicId);
    if (info.chapters.isEmpty) throw StateError('漫画没有章节');
    comicChapterId = info.chapters.first.id;
    stdout.writeln('   ${info.title} · ${info.chapters.length} 话');
  });

  await check('getComicContent', () async {
    final content = await api.getComicContent(
      chapterId: comicChapterId,
      take: 1,
    );
    if (content.chapter.images.isEmpty) throw StateError('漫画章节没有图片');
    stdout.writeln(
      '   ${content.chapter.title} · ${content.chapter.images.length}/${content.chapter.total} 页',
    );
  });

  await check('getComments', () async {
    final page = await api.getComments(
      type: CommentTargetType.book,
      id: bookId,
      page: 1,
    );
    stdout.writeln('   ${page.items.length} 条评论 / 共 ${page.totalPages} 页');
  });

  // 用一个不存在的书籍 ID 触发服务端的业务校验：既能确认枚举名参数被正确绑定
  // （绑定失败会返回「error on the server」），又不会真的产生评论。
  await check('postComment(编码校验)', () async {
    try {
      await api.postComment(
        type: CommentTargetType.book,
        id: 2147483000,
        content: '编码校验',
      );
    } on ApiError catch (error) {
      if (error.message.contains('error on the server')) rethrow;
      stdout.writeln('   业务校验生效：${error.message}');
      return;
    }
    throw StateError('评论竟然发布到了不存在的书籍上');
  });

  await check('getComicSeriesByIds', () async {
    final history = await api.getReadHistory();
    final ids = history.comicIds.take(6).toList();
    if (ids.isEmpty) {
      stdout.writeln('   历史里没有漫画，跳过');
      return;
    }
    final page = await api.getComicSeriesByIds(ids);
    stdout.writeln('   ${page.items.length} 部漫画');
  });

  await check('getBookShelf', () async {
    final shelf = await api.getBookShelf();
    stdout.writeln('   ${shelf.items.length} 个条目 · 版本 ${shelf.version}');
  });

  await check('getReadHistory', () async {
    final history = await api.getReadHistory();
    stdout.writeln(
      '   小说 ${history.novelIds.length} · 漫画 ${history.comicIds.length}',
    );
  });

  await check('getMyProfile', () async {
    final profile = await api.getMyProfile();
    stdout.writeln('   ${profile.userName} · 等级 ${profile.growth.level}');
  });

  await check('getCommunityHome', () async {
    final home = await api.getCommunityHome(const CommunityListQuery());
    stdout.writeln(
      '   ${home.boards.length} 个版块 · ${home.feed.length} 个帖子 · 热帖 ${home.hotThreads.length}',
    );
  });

  await check('getCommunityThread', () async {
    final home = await api.getCommunityHome(const CommunityListQuery());
    if (home.feed.isEmpty) throw StateError('没有帖子');
    final thread = await api.getCommunityThread(threadId: home.feed.first.id);
    stdout.writeln(
      '   ${thread?.item.title} · ${thread?.replyItems.length} 条回复',
    );
  });

  await check('getNotifications', () async {
    final page = await api.getNotifications(page: 1, size: 5);
    stdout.writeln('   ${page.items.length} 条通知');
  });

  await signalR.dispose();
  stdout.writeln(failures == 0 ? '\n全部通过' : '\n$failures 项失败');
  exitCode = failures == 0 ? 0 : 1;
}
