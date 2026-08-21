import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import '../../core/network/signalr_connection.dart';
import 'decode.dart';
import 'endpoints.dart';
import 'envelope.dart';

// 端点按领域拆成 extension，调用点只 import 这一个文件就能全都看见。
export 'api_client_account.dart';
export 'api_client_catalog.dart';
export 'api_client_comments.dart';
export 'api_client_community.dart';
export 'requests.dart';

/// 401 时调用去刷新令牌；返回 false 表示刷不动了。
typedef AuthRetryHandler = Future<bool> Function();

class SessionTokens {
  const SessionTokens({required this.sessionToken, required this.refreshToken});

  final String sessionToken;
  final String refreshToken;

  static SessionTokens decode(Object? value) {
    final envelope = asRecord(value, '登录响应');
    throwIfFailed(envelope, '登录失败。');
    final response =
        asRecordOrNull(envelope['Response'] ?? envelope['response']) ??
        envelope;
    return SessionTokens(
      sessionToken: asString(response['Token'] ?? response['token']),
      refreshToken: asString(
        response['RefreshToken'] ?? response['refreshToken'],
      ),
    );
  }
}

class ApiClient {
  ApiClient({
    required SignalRConnection signalR,
    required RateLimitRequestScheduler scheduler,
    required Future<Map<String, String>> Function() headers,
    this.authRetry,
  }) : _signalR = signalR,
       _scheduler = scheduler,
       _headers = headers;

  /// 服务端对批量取书有硬上限。
  static const int batchIdLimit = 24;

  final SignalRConnection _signalR;
  final RateLimitRequestScheduler _scheduler;
  final Future<Map<String, String>> Function() _headers;
  AuthRetryHandler? authRetry;

  Future<T> invoke<T>(
    String methodName,
    Object? params,
    T Function(Object? value) decode, {
    RequestPriority priority = RequestPriority.interactive,
    CancelToken? cancelToken,
  }) async {
    for (var hasRetried = false; ; hasRetried = true) {
      if (cancelToken?.isCancelled ?? false) {
        throw const RequestCancelledError();
      }
      Object? envelope;
      try {
        envelope = await _scheduler.add(
          () => _signalR.invoke(methodName, <Object?>[
            params,
            <String, Object?>{'UseGzip': true},
          ]),
          priority: priority,
          cancelToken: cancelToken,
        );
      } catch (error) {
        if (error is RequestCancelledError ||
            (cancelToken?.isCancelled ?? false)) {
          throw const RequestCancelledError();
        }
        final apiError = toApiError(error);
        if (!apiError.isAuth || hasRetried || authRetry == null) throw apiError;
        // 会话令牌只在建连时校验，刷新后必须重连才带得上新令牌。
        if (!await authRetry!()) throw apiError;
        await _signalR.reset();
        continue;
      }
      return decode(unwrapSignalRResponse(envelope));
    }
  }

  // 以下四个是内部管道，只因 extension 在别的库里看不见 `_` 成员才公开。
  Future<http.Response> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('${ServiceEndpoints.apiOrigin}$path')
        .replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...await _headers(),
    };
    return _scheduler.add(() async {
      final client = http.Client();
      try {
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) request.body = jsonEncode(body);
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        return await http.Response.fromStream(streamed);
      } finally {
        client.close();
      }
    });
  }

  Object? decodeHttpBody(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// 裸 HTTP 的状态码 → ApiError 唯一映射点。哪些状态算「登录失效」由调用方定：
  /// 刷新令牌过期回的是 404，而验证码填错回 401 却不该把用户踢下线。
  void ensureOk(
    http.Response response,
    String message, {
    Set<int> authStatuses = const <int>{401},
  }) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    throw ApiError(
      message,
      authStatuses.contains(status)
          ? ApiErrorCategory.auth
          : ApiErrorCategory.server,
      status: status,
    );
  }

  /// 2xx 之后还要看信封里的失败位；正文不是对象时（例如空响应）返回 null。
  Map<String, dynamic>? envelopeOf(http.Response response, String fallback) {
    final body = asRecordOrNull(decodeHttpBody(response));
    if (body != null) throwIfFailed(body, fallback);
    return body;
  }

  /// 分页参数下界：服务端拿到 0 页会返回空列表，静默变成「没有更多」。
  static int atLeastOne(int value) => value < 1 ? 1 : value;

  static List<int> normalizeBatchIds(List<int> ids) {
    final unique = ids.toSet().toList();
    if (unique.length > batchIdLimit) {
      throw ArgumentError('单次批量请求最多 $batchIdLimit 本书。');
    }
    return unique;
  }
}
