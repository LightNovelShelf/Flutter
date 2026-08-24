import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

enum ApiErrorCategory { auth, network, server, unknown }

class ApiError implements Exception {
  const ApiError(this.message, this.category, {this.status, this.cause});

  final String message;
  final ApiErrorCategory category;
  final int? status;
  final Object? cause;

  bool get isAuth => category == ApiErrorCategory.auth;

  @override
  String toString() =>
      'ApiError($category${status == null ? '' : ' $status'}): $message';
}

/// 请求还没发出就被取消。
class RequestCancelledError implements Exception {
  const RequestCancelledError();

  @override
  String toString() => 'RequestCancelledError';
}

final RegExp _authMessagePattern = RegExp(
  r'401|unauthori[sz]ed|invalid token|no\s*token|notoken|无效token|未登录|授权|unauthorized',
  caseSensitive: false,
);

/// 真正的传输层故障：连不上、握手失败、连接中断、超时。只有这些重试才有意义。
bool isNetworkFailure(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is WebSocketException ||
    error is HandshakeException ||
    error is http.ClientException ||
    error is TimeoutException;

/// 把任意异常规整成 [ApiError]。认不出来的归 `unknown`，不当成网络问题重试。
ApiError toApiError(Object error) {
  if (error is ApiError) return error;
  if (_authMessagePattern.hasMatch(error.toString())) {
    return ApiError('需要登录后才能继续。', ApiErrorCategory.auth, cause: error);
  }
  if (isNetworkFailure(error)) {
    return ApiError('无法连接到轻书架服务器。', ApiErrorCategory.network, cause: error);
  }
  // 认不出来的原样透出，页面显示真实原因；`fallback` 只管消息为空的情况。
  return ApiError(error.toString(), ApiErrorCategory.unknown, cause: error);
}

/// 统一的用户可见错误文案：认证/网络给固定提示，其余沿用服务端消息。
///
/// `normalize` 为真时先把任意异常规整成 [ApiError]（只有传输层故障落到网络分支，
/// 其余原样透出），否则非 [ApiError] 直接用 `fallback`。
String describeApiError(
  Object error, {
  String fallback = '发生了预料之外的错误，请稍后再试。',
  String auth = '登录状态已失效，请重新登录后再试。',
  String network = '网络连接不可用，请检查网络后重试。',
  bool normalize = false,
}) {
  if (error is ApiError) {
    return switch (error.category) {
      ApiErrorCategory.auth => auth,
      ApiErrorCategory.network => network,
      _ => error.message.trim().isEmpty ? fallback : error.message,
    };
  }
  if (error is RequestCancelledError) return '请求已取消。';
  if (!normalize) return fallback;
  return describeApiError(
    toApiError(error),
    fallback: fallback,
    auth: auth,
    network: network,
  );
}

/// 判断是否为取消，取消异常可能被包在 [ApiError.cause] 里。
bool isCancellation(Object error) =>
    error is RequestCancelledError ||
    (error is ApiError && error.cause is RequestCancelledError);
