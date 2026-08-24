import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_error.dart';

/// 全局重试策略，由 `main` 挂到 `ProviderScope` 上。
///
/// Riverpod 默认对任意 Exception 退避重试十次（累计约 38 秒）。只有传输层故障重试
/// 才有意义，业务错误和取消重试多少次都是同一个结果，直接抛给页面显示。
Duration? apiRetry(int retryCount, Object error) {
  if (isCancellation(error)) return null;
  if (error is! ApiError || error.category != ApiErrorCategory.network) {
    return null;
  }
  return ProviderContainer.defaultRetry(retryCount, error, maxRetries: 3);
}
