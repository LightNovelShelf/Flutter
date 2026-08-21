import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/network/request_scheduler.dart';
import '../core/network/signalr_connection.dart';
import '../core/platform/stores.dart';
import 'api/api_client.dart';
import 'api/endpoints.dart';
import 'session/auth_controller.dart';
import 'settings/app_settings.dart';

/// 应用启动时一次性构建的运行时依赖。
class AppRuntime {
  AppRuntime({
    required this.credentials,
    required this.keyValueStore,
    required this.settings,
    required this.signalR,
    required this.api,
    required this.auth,
    required this.hasStoredSession,
  });

  final CredentialStore credentials;
  final KeyValueStore keyValueStore;
  final SettingsController settings;
  final SignalRConnection signalR;
  final ApiClient api;
  final AuthController auth;
  final bool hasStoredSession;

  static Future<AppRuntime> bootstrap() async {
    final credentials = SecureCredentialStore();
    final keyValueStore = await PreferencesKeyValueStore.open();
    final settings = await SettingsController.load(keyValueStore);
    final scheduler = RateLimitRequestScheduler();

    final userAgent = await _backendUserAgent();
    Future<String> visitorId() async {
      final existing = await credentials.read(AuthCredentialKeys.visitorId);
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = _randomUuid();
      await credentials.write(AuthCredentialKeys.visitorId, generated);
      return generated;
    }

    Future<Map<String, String>> backendHeaders() async => <String, String>{
          'User-Agent': userAgent,
          'x-id': await visitorId(),
        };

    final signalR = SignalRConnection(
      endpoint: ServiceEndpoints.signalRHub,
      accessTokenFactory: () =>
          credentials.read(AuthCredentialKeys.sessionToken),
      headersFactory: backendHeaders,
    );

    final api = ApiClient(
      signalR: signalR,
      scheduler: scheduler,
      headers: () async {
        final token = await credentials.read(AuthCredentialKeys.sessionToken);
        return <String, String>{
          ...await backendHeaders(),
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        };
      },
    );

    final auth = AuthController(
      api: api,
      credentials: credentials,
      signalR: signalR,
    );
    api.authRetry = auth.refresh;

    return AppRuntime(
      credentials: credentials,
      keyValueStore: keyValueStore,
      settings: settings,
      signalR: signalR,
      api: api,
      auth: auth,
      hasStoredSession: await auth.hasStoredSession(),
    );
  }

  /// 恢复会话并建立实时连接；失败时降级为未登录。
  Future<void> start() async {
    try {
      final restored = await auth.bootstrap();
      if (restored) await signalR.connect();
    } catch (error) {
      debugPrint('会话初始化失败：$error');
    }
  }
}

/// HTTP 头只允许 ASCII，因此不能直接用本地化的应用名，固定用英文标识加版本号。
Future<String> _backendUserAgent() async {
  const String name = 'LightNovelShelf';
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version.isEmpty ? name : '$name/${info.version}';
  } catch (_) {
    return name;
  }
}

String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
