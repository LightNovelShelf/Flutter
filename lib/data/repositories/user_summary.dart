import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';

class _CachedSummary {
  const _CachedSummary(this.value, this.expiresAt);

  final PublicUserSummary value;
  final DateTime expiresAt;
}

/// 用户名片资料的内存缓存：命中且未过期就不再请求，满了淘汰最久没用到的那个。
/// 名片是反复打开的轻量弹窗，同一个人来回点不该每次都打一趟服务端。
class UserSummaryCache {
  UserSummaryCache(
    this._api, {
    this.ttl = const Duration(minutes: 5),
    this.capacity = 20,
  });

  final ApiClient _api;
  final Duration ttl;
  final int capacity;

  /// LinkedHashMap 保持插入顺序，命中后重新插到队尾，队首就是最久未用的那条。
  final LinkedHashMap<int, _CachedSummary> _entries =
      LinkedHashMap<int, _CachedSummary>();

  /// 同一个人并发打开只发一次请求。
  final Map<int, Future<PublicUserSummary>> _pending =
      <int, Future<PublicUserSummary>>{};

  /// 未命中或已过期返回 null。
  PublicUserSummary? read(int userId) {
    final entry = _entries.remove(userId);
    if (entry == null) return null;
    if (!DateTime.now().isBefore(entry.expiresAt)) return null;
    _entries[userId] = entry;
    return entry.value;
  }

  Future<PublicUserSummary> load(int userId) {
    final cached = read(userId);
    if (cached != null) return Future<PublicUserSummary>.value(cached);

    final pending = _pending[userId];
    if (pending != null) return pending;

    // 成功和失败都在同一条链上收尾，避免派生出没人接的 future 把异常报成未处理。
    final request = _api
        .getUserSummary(userId)
        .then(
          (value) {
            _pending.remove(userId);
            _store(userId, value);
            return value;
          },
          onError: (Object error, StackTrace stack) {
            // 失败不写缓存，重试会重新请求。
            _pending.remove(userId);
            Error.throwWithStackTrace(error, stack);
          },
        );
    _pending[userId] = request;
    return request;
  }

  void _store(int userId, PublicUserSummary value) {
    _entries.remove(userId);
    _entries[userId] = _CachedSummary(value, DateTime.now().add(ttl));
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}

final Provider<UserSummaryCache> userSummaryCacheProvider =
    Provider<UserSummaryCache>(
      (ref) => UserSummaryCache(ref.watch(apiClientProvider)),
    );

/// 用户名片的数据源，实际读写都走 [UserSummaryCache]。
final FutureProviderFamily<PublicUserSummary, int> userSummaryProvider =
    FutureProvider.family<PublicUserSummary, int>(
      (ref, userId) => ref.watch(userSummaryCacheProvider).load(userId),
      isAutoDispose: true,
    );
