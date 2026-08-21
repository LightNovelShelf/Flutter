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

ApiError toApiError(Object error) {
  if (error is ApiError) return error;
  final message = error.toString();
  final isAuth = _authMessagePattern.hasMatch(message);
  return ApiError(
    isAuth ? '需要登录后才能继续。' : '无法连接到轻书架服务器。',
    isAuth ? ApiErrorCategory.auth : ApiErrorCategory.network,
    cause: error,
  );
}

/// 统一的用户可见错误文案：认证/网络给固定提示，其余沿用服务端消息。
///
/// `normalize` 为真时先把任意异常规整成 [ApiError]（socket 异常等会落到网络分支），
/// 否则非 [ApiError] 直接用 `fallback`。
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

/// 页面切换、筛选变更会主动取消在途请求；取消可能被包在 [ApiError.cause] 里。
bool isCancellation(Object error) =>
    error is RequestCancelledError ||
    (error is ApiError && error.cause is RequestCancelledError);
