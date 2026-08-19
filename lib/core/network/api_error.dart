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
