import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_error.dart';

/// SignalR 帧分隔符。
const String _recordSeparator = '\u001e';

const Duration _handshakeTimeout = Duration(seconds: 30);
const Duration _invokeTimeout = Duration(seconds: 30);
const Duration _pingInterval = Duration(seconds: 15);

/// 服务端主动推送（如 `OnMessage` 公告）。
class ServerInvocation {
  const ServerInvocation(this.target, this.arguments);

  final String target;
  final List<Object?> arguments;
}

enum SignalRState { disconnected, connecting, connected, reconnecting }

/// 精简版 SignalR Hub 客户端（JSON 协议 + WebSocket + skipNegotiation）。
///
/// 服务端 JSON、MessagePack 两种协议都挂着；选 JSON：`byte[]` 以 base64 返回，
/// 配合 `UseGzip` 就能拿到压缩响应体，Dart 侧不必实现 MessagePack。
class SignalRConnection {
  SignalRConnection({
    required this.endpoint,
    required this.accessTokenFactory,
    this.headersFactory,
    this.onStateChanged,
  });

  final String endpoint;
  final Future<String?> Function() accessTokenFactory;
  final Future<Map<String, String>> Function()? headersFactory;
  final void Function(SignalRState state)? onStateChanged;

  final Map<String, Completer<Object?>> _pending =
      <String, Completer<Object?>>{};
  final StreamController<ServerInvocation> _serverMessages =
      StreamController<ServerInvocation>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Completer<void>? _handshake;
  Future<void>? _connecting;
  int _invocationId = 0;
  int _generation = 0;
  bool _desiredConnected = false;
  int _retryCount = 0;
  SignalRState _state = SignalRState.disconnected;

  SignalRState get state => _state;
  bool get isConnected => _state == SignalRState.connected;
  Stream<ServerInvocation> get serverMessages => _serverMessages.stream;

  void _setState(SignalRState next) {
    if (_state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }

  Future<void> connect() {
    _desiredConnected = true;
    if (_state == SignalRState.connected) return Future<void>.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _setState(SignalRState.connecting);

    final token = await accessTokenFactory();
    final headers = <String, String>{
      if (headersFactory != null) ...await headersFactory!(),
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final uri = _buildSocketUri(token);
    if (generation != _generation || !_desiredConnected) {
      throw const ApiError('连接已取消。', ApiErrorCategory.network);
    }

    late final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(_handshakeTimeout);
    } catch (error) {
      _setState(SignalRState.disconnected);
      throw toApiError(error);
    }

    final channel = IOWebSocketChannel(socket);
    _channel = channel;
    final handshake = Completer<void>();
    _handshake = handshake;

    _subscription = channel.stream.listen(
      _onData,
      onError: (Object error) => _onClosed(generation, error),
      onDone: () => _onClosed(generation, null),
      cancelOnError: false,
    );

    channel.sink.add('{"protocol":"json","version":1}$_recordSeparator');

    try {
      await handshake.future.timeout(_handshakeTimeout);
    } catch (error) {
      await _teardown();
      _setState(SignalRState.disconnected);
      throw toApiError(error);
    }

    _retryCount = 0;
    _setState(SignalRState.connected);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_state != SignalRState.connected) return;
      _send(<String, Object?>{'type': 6});
    });
  }

  Uri _buildSocketUri(String? token) {
    final base = Uri.parse(endpoint);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final query = Map<String, String>.of(base.queryParameters);
    if (token != null && token.isNotEmpty) query['access_token'] = token;
    return base.replace(
      scheme: scheme,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  void _onData(dynamic data) {
    final text = data is String ? data : utf8.decode((data as List<int>));
    for (final frame in text.split(_recordSeparator)) {
      if (frame.isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(frame);
      } catch (_) {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;
      _handleMessage(decoded);
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      final error = message['error'];
      if (error is String) {
        handshake.completeError(ApiError(error, ApiErrorCategory.server));
      } else {
        handshake.complete();
      }
      return;
    }

    switch (message['type']) {
      case 1: // 服务端调用
      case 4:
        final target = message['target'];
        if (target is String) {
          _serverMessages.add(
            ServerInvocation(
              target,
              (message['arguments'] as List<dynamic>?)?.cast<Object?>() ??
                  const <Object?>[],
            ),
          );
        }
      case 3: // 调用完成
        final id = message['invocationId'];
        if (id is! String) return;
        final completer = _pending.remove(id);
        if (completer == null || completer.isCompleted) return;
        final error = message['error'];
        if (error is String) {
          completer.completeError(ApiError(error, _categoryForHubError(error)));
        } else {
          completer.complete(message['result']);
        }
      case 7: // 连接关闭
        final error = message['error'];
        _onClosed(
          _generation,
          error is String ? ApiError(error, ApiErrorCategory.server) : null,
        );
      default:
        break;
    }
  }

  ApiErrorCategory _categoryForHubError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('unauthorized') || lower.contains('401')
        ? ApiErrorCategory.auth
        : ApiErrorCategory.server;
  }

  void _send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add('${jsonEncode(message)}$_recordSeparator');
  }

  Future<Object?> invoke(String target, List<Object?> arguments) async {
    await connect();
    final id = (++_invocationId).toString();
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send(<String, Object?>{
      'type': 1,
      'invocationId': id,
      'target': target,
      'arguments': arguments,
    });
    try {
      return await completer.future.timeout(_invokeTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw const ApiError('请求超时。', ApiErrorCategory.network);
    }
  }

  void _onClosed(int generation, Object? error) {
    if (generation != _generation) return;
    _pingTimer?.cancel();
    _pingTimer = null;

    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(
        error ?? const ApiError('连接已关闭。', ApiErrorCategory.network),
      );
    }

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          error ?? const ApiError('连接已关闭。', ApiErrorCategory.network),
        );
      }
    }
    _pending.clear();

    unawaited(_teardown());

    if (!_desiredConnected) {
      _setState(SignalRState.disconnected);
      return;
    }

    _setState(SignalRState.reconnecting);
    final delays = <int>[0, 5000, 10000, 20000];
    final delay = _retryCount < delays.length ? delays[_retryCount] : 30000;
    _retryCount += 1;
    Timer(Duration(milliseconds: delay), () {
      if (!_desiredConnected) return;
      unawaited(connect().catchError((_) {}));
    });
  }

  Future<void> _teardown() async {
    final subscription = _subscription;
    _subscription = null;
    final channel = _channel;
    _channel = null;
    _handshake = null;
    await subscription?.cancel();
    await channel?.sink.close();
  }

  Future<void> close() async {
    _desiredConnected = false;
    _generation += 1;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _teardown();
    _setState(SignalRState.disconnected);
  }

  /// 登录/登出后调用：断掉旧连接，下次调用时带新凭据重连。
  Future<void> reset() async {
    await close();
  }

  Future<void> dispose() async {
    await close();
    await _serverMessages.close();
  }
}
