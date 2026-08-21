import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 站内网络图片共用的 CacheManager。
///
/// 不用 `DefaultCacheManager`：它的 sqflite 元数据每次读写都过 platform channel，
/// 回包在 UI isolate 解码，实测单次回调占用 17~30ms 帧预算并触发 minor GC。
/// `JsonCacheInfoRepository` 是纯 Dart 实现，不走 channel。
final CacheManager appImageCacheManager = CacheManager(
  Config(
    _cacheKey,
    repo: JsonCacheInfoRepository(databaseName: _cacheKey),
  ),
);

const String _cacheKey = 'lightnovelImageCache';
