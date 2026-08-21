import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/shared/paging/paged_list.dart';
import 'package:lightnovel/shared/paging/paged_list_controller.dart';

/// 分页控制器测试桩：每页的 fetch 行为由 [handler] 决定。
class _TestController extends PagedListController<int, void> {
  _TestController() : super(null);

  final List<int> requestedPages = <int>[];
  late Future<FetchedPage<int>> Function(int page) handler;

  @override
  void subscribe() {}

  @override
  int idOf(int item) => item;

  @override
  Future<FetchedPage<int>> fetchPage(int page) {
    requestedPages.add(page);
    return handler(page);
  }
}

FetchedPage<int> _page(List<int> items, int page, int totalPages) =>
    FetchedPage<int>(items: items, page: page, totalPages: totalPages);

void main() {
  late _TestController controller;
  late ProviderContainer container;
  late NotifierProvider<_TestController, PagedList<int>> provider;

  setUp(() {
    controller = _TestController();
    provider = NotifierProvider<_TestController, PagedList<int>>(
      () => controller,
    );
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('首屏落地后暴露数据与页码', () async {
    controller.handler = (page) async => _page(<int>[1, 2], page, 3);
    expect(container.read(provider).loading, isTrue);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(provider);
    expect(state.loading, isFalse);
    expect(state.items, <int>[1, 2]);
    expect(state.page, 1);
    expect(state.hasMore, isTrue);
  });

  test('翻页按 id 去重追加，不重复已有条目', () async {
    controller.handler = (page) async =>
        _page(page == 1 ? <int>[1, 2] : <int>[2, 3], page, 2);
    container.read(provider);
    await Future<void>.delayed(Duration.zero);
    await container.read(provider.notifier).loadMore();
    final state = container.read(provider);
    expect(state.items, <int>[1, 2, 3]);
    expect(state.hasMore, isFalse);
  });

  test('翻页失败只写 loadMoreError，已有数据保留', () async {
    controller.handler = (page) async {
      if (page == 1) return _page(<int>[1], page, 2);
      throw const ApiError('炸了', ApiErrorCategory.server);
    };
    container.read(provider);
    await Future<void>.delayed(Duration.zero);
    await container.read(provider.notifier).loadMore();
    final state = container.read(provider);
    expect(state.items, <int>[1]);
    expect(state.error, isNull);
    expect(state.loadMoreError, '炸了');
    expect(state.loadingMore, isFalse);
  });

  test('refresh 保留旧数据，retry 清空重来', () async {
    controller.handler = (page) async => _page(<int>[1], page, 2);
    container.read(provider);
    await Future<void>.delayed(Duration.zero);

    final refresh = container.read(provider.notifier).refresh();
    expect(container.read(provider).items, <int>[1]);
    expect(container.read(provider).refreshing, isTrue);
    await refresh;

    final retry = container.read(provider.notifier).retry();
    expect(container.read(provider).items, isEmpty);
    expect(container.read(provider).loading, isTrue);
    await retry;
  });

  test('旧响应晚到不会覆盖新一轮结果', () async {
    final slow = Completer<FetchedPage<int>>();
    controller.handler = (page) async {
      if (controller.requestedPages.length == 1) return slow.future;
      return _page(<int>[9], page, 1);
    };
    container.read(provider);
    await Future<void>.delayed(Duration.zero);
    final second = container.read(provider.notifier).retry();
    await second;
    slow.complete(_page(<int>[1, 2, 3], 1, 5));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).items, <int>[9]);
    expect(container.read(provider).totalPages, 1);
  });

  test('取消不产生用户可见错误', () async {
    controller.handler = (page) async => throw const RequestCancelledError();
    container.read(provider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).error, isNull);
  });

  test('mergeById 在增量为空时返回同一实例', () {
    final existing = <int>[1, 2];
    expect(
      identical(mergeById(existing, <int>[], (item) => item), existing),
      isTrue,
    );
  });

  group('describeApiError', () {
    test('认证与网络走定制文案', () {
      expect(
        describeApiError(
          const ApiError('x', ApiErrorCategory.auth),
          auth: '请登录',
        ),
        '请登录',
      );
      expect(
        describeApiError(
          const ApiError('x', ApiErrorCategory.network),
          network: '断网了',
        ),
        '断网了',
      );
    });

    test('服务端消息优先，空白时回落', () {
      expect(
        describeApiError(const ApiError('服务端说明', ApiErrorCategory.server)),
        '服务端说明',
      );
      expect(
        describeApiError(
          const ApiError('   ', ApiErrorCategory.server),
          fallback: '兜底',
        ),
        '兜底',
      );
    });

    test('normalize 把任意异常按网络错误处理', () {
      expect(
        describeApiError(
          const SocketFailure(),
          network: '断网了',
          normalize: true,
        ),
        '断网了',
      );
      expect(describeApiError(const SocketFailure(), fallback: '兜底'), '兜底');
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();

  @override
  String toString() => 'SocketFailure';
}
