import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_error.dart';
import '../../core/network/signalr_connection.dart';
import '../../core/platform/stores.dart';
import '../api/api_client.dart';

class AuthCredentialKeys {
  const AuthCredentialKeys._();

  static const String refreshToken = 'lightnovel.refresh-token';
  static const String sessionToken = 'lightnovel.session-token';
  static const String visitorId = 'lightnovel.visitor-id';
}

enum AuthenticationStatus {
  unknown,
  refreshing,
  signingIn,
  registering,
  authenticated,
  signedOut,
  signingOut,
}

@immutable
class AuthenticationSnapshot {
  const AuthenticationSnapshot({required this.status, this.error});

  final AuthenticationStatus status;
  final String? error;

  bool get isAuthenticated => status == AuthenticationStatus.authenticated;

  bool get isBusy =>
      status == AuthenticationStatus.refreshing ||
      status == AuthenticationStatus.signingIn ||
      status == AuthenticationStatus.registering ||
      status == AuthenticationStatus.signingOut;
}

final RegExp _emailPattern =
    RegExp(r'^\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$', caseSensitive: false);

/// 认证状态机：登录、注册、刷新、登出。凭据写入串行化，revision 用于丢弃被新
/// 操作取代的旧结果。
class AuthController extends ChangeNotifier {
  AuthController({
    required ApiClient api,
    required CredentialStore credentials,
    required SignalRConnection signalR,
    PasswordHasher hasher = const PasswordHasher(),
  })  : _api = api,
        _credentials = credentials,
        _signalR = signalR,
        _hasher = hasher;

  final ApiClient _api;
  final CredentialStore _credentials;
  final SignalRConnection _signalR;
  final PasswordHasher _hasher;

  int _revision = 0;
  Future<void> _credentialWrite = Future<void>.value();
  ({int revision, String refreshToken, Future<bool> promise})? _refreshInFlight;

  AuthenticationSnapshot _snapshot =
      const AuthenticationSnapshot(status: AuthenticationStatus.unknown);

  AuthenticationSnapshot get snapshot => _snapshot;

  void _publish(AuthenticationSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }

  Future<T> _enqueueCredentialWrite<T>(Future<T> Function() operation) {
    final next = _credentialWrite.then((_) => operation(), onError: (_) => operation());
    _credentialWrite = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<bool> _persistTokens(SessionTokens tokens, int expectedRevision) =>
      _enqueueCredentialWrite(() async {
        if (expectedRevision != _revision) return false;
        await _credentials.write(
          AuthCredentialKeys.refreshToken,
          tokens.refreshToken,
        );
        if (expectedRevision != _revision) return false;
        await _credentials.write(
          AuthCredentialKeys.sessionToken,
          tokens.sessionToken,
        );
        return expectedRevision == _revision;
      });

  Future<void> _clearCredentials(int expectedRevision) =>
      _enqueueCredentialWrite(() async {
        if (expectedRevision != _revision) return;
        await _credentials.delete(AuthCredentialKeys.sessionToken);
        await _credentials.delete(AuthCredentialKeys.refreshToken);
      });

  static bool _isInvalidRefreshError(Object error) =>
      error is ApiError &&
      error.isAuth &&
      (error.status == 401 || error.status == 404 || error.status == -100);

  Future<bool> _performRefresh(int expectedRevision, String refreshToken) async {
    try {
      final sessionToken = await _api.refreshToken(refreshToken);
      final persisted = await _enqueueCredentialWrite(() async {
        if (expectedRevision != _revision) return false;
        await _credentials.write(AuthCredentialKeys.sessionToken, sessionToken);
        return expectedRevision == _revision;
      });
      if (!persisted) return false;
      _revision += 1;
      _publish(
        const AuthenticationSnapshot(status: AuthenticationStatus.authenticated),
      );
      return true;
    } catch (error) {
      if (expectedRevision != _revision) return false;
      if (_isInvalidRefreshError(error)) {
        _revision += 1;
        await _clearCredentials(_revision);
        _publish(
          const AuthenticationSnapshot(status: AuthenticationStatus.signedOut),
        );
        return false;
      }
      _publish(
        AuthenticationSnapshot(
          status: AuthenticationStatus.signedOut,
          error: error is ApiError ? error.message : '无法恢复登录状态。',
        ),
      );
      return false;
    }
  }

  Future<bool> refresh() async {
    final expectedRevision = _revision;
    final refreshToken = await _credentials.read(AuthCredentialKeys.refreshToken);
    if (expectedRevision != _revision) return false;
    if (refreshToken == null || refreshToken.isEmpty) {
      _publish(
        const AuthenticationSnapshot(status: AuthenticationStatus.signedOut),
      );
      return false;
    }

    final shared = _refreshInFlight;
    if (shared != null &&
        shared.revision == expectedRevision &&
        shared.refreshToken == refreshToken) {
      return shared.promise;
    }

    _publish(const AuthenticationSnapshot(status: AuthenticationStatus.refreshing));
    final promise = _performRefresh(expectedRevision, refreshToken);
    _refreshInFlight = (
      revision: expectedRevision,
      refreshToken: refreshToken,
      promise: promise,
    );
    try {
      return await promise;
    } finally {
      if (identical(_refreshInFlight?.promise, promise)) _refreshInFlight = null;
    }
  }

  /// 启动时恢复登录状态。
  Future<bool> bootstrap() async {
    if (_snapshot.isAuthenticated) return true;
    final restored = await refresh();
    if (!restored && _snapshot.error != null) {
      throw ApiError(_snapshot.error!, ApiErrorCategory.network);
    }
    return restored;
  }

  Future<bool> hasStoredSession() async {
    final token = await _credentials.read(AuthCredentialKeys.refreshToken);
    return token != null && token.isNotEmpty;
  }

  static String _normalizeAndValidateEmail(String email) {
    final normalized = email.trim();
    if (!_emailPattern.hasMatch(normalized)) {
      throw const ApiError('请输入有效的邮箱地址。', ApiErrorCategory.unknown);
    }
    return normalized;
  }

  static void _assertPassword(String password, String confirmation) {
    if (password.length < 6) {
      throw const ApiError('密码至少需要 6 位。', ApiErrorCategory.unknown);
    }
    if (password != confirmation) {
      throw const ApiError('两次输入的密码不一致。', ApiErrorCategory.unknown);
    }
  }

  Future<void> signIn(String email, String password) async {
    final normalizedEmail = _normalizeAndValidateEmail(email);
    if (password.isEmpty) {
      throw const ApiError('请输入密码。', ApiErrorCategory.unknown);
    }
    final expectedRevision = ++_revision;
    _publish(const AuthenticationSnapshot(status: AuthenticationStatus.signingIn));
    try {
      await _clearCredentials(expectedRevision);
      final tokens = await _api.login(
        email: normalizedEmail,
        passwordHash: _hasher.sha256Hex(password),
      );
      if (!await _persistTokens(tokens, expectedRevision)) {
        throw const ApiError('登录已被取消。', ApiErrorCategory.unknown);
      }
      _publish(
        const AuthenticationSnapshot(status: AuthenticationStatus.authenticated),
      );
      await _signalR.reset();
    } catch (error) {
      if (expectedRevision == _revision) {
        _publish(
          AuthenticationSnapshot(
            status: AuthenticationStatus.signedOut,
            error: error is ApiError ? error.message : '无法登录。',
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> register({
    required String userName,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String code,
    String inviteCode = '',
  }) async {
    final normalizedUserName = userName.trim();
    final normalizedEmail = _normalizeAndValidateEmail(email);
    final normalizedCode = code.trim();
    if (normalizedUserName.isEmpty) {
      throw const ApiError('请输入用户名。', ApiErrorCategory.unknown);
    }
    _assertPassword(password, passwordConfirmation);
    if (normalizedCode.isEmpty) {
      throw const ApiError('请输入验证码。', ApiErrorCategory.unknown);
    }

    final expectedRevision = ++_revision;
    _publish(const AuthenticationSnapshot(status: AuthenticationStatus.registering));
    try {
      await _clearCredentials(expectedRevision);
      final tokens = await _api.register(
        userName: normalizedUserName,
        email: normalizedEmail,
        passwordHash: _hasher.sha256Hex(password),
        code: normalizedCode,
        inviteCode: inviteCode.trim(),
      );
      if (!await _persistTokens(tokens, expectedRevision)) {
        throw const ApiError('注册已被取消。', ApiErrorCategory.unknown);
      }
      _publish(
        const AuthenticationSnapshot(status: AuthenticationStatus.authenticated),
      );
      await _signalR.reset();
    } catch (error) {
      if (expectedRevision == _revision) {
        _publish(
          AuthenticationSnapshot(
            status: AuthenticationStatus.signedOut,
            error: error is ApiError ? error.message : '无法创建账号。',
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> sendRegisterCode(String email) =>
      _api.sendRegisterEmail(_normalizeAndValidateEmail(email));

  Future<void> sendResetCode(String email) =>
      _api.sendResetEmail(_normalizeAndValidateEmail(email));

  Future<void> resetPassword({
    required String email,
    required String password,
    required String passwordConfirmation,
    required String code,
  }) async {
    final normalizedEmail = _normalizeAndValidateEmail(email);
    final normalizedCode = code.trim();
    _assertPassword(password, passwordConfirmation);
    if (normalizedCode.isEmpty) {
      throw const ApiError('请输入验证码。', ApiErrorCategory.unknown);
    }
    await _api.resetPassword(
      email: normalizedEmail,
      newPasswordHash: _hasher.sha256Hex(password),
      code: normalizedCode,
    );
  }

  Future<void> signOut() async {
    final expectedRevision = ++_revision;
    _publish(const AuthenticationSnapshot(status: AuthenticationStatus.signingOut));
    await _clearCredentials(expectedRevision);
    await _signalR.close();
    _publish(const AuthenticationSnapshot(status: AuthenticationStatus.signedOut));
  }
}
