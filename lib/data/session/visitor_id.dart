import 'dart:math';

import '../../core/platform/stores.dart';
import 'auth_controller.dart';

/// 匿名访客标识，首次启动随机生成后长期保存，作为 `x-id` 请求头发给服务端。
class VisitorId {
  VisitorId({required CredentialStore credentials})
    : _credentials = credentials;

  final CredentialStore _credentials;

  /// 缓存 Future 而不是结果：首启时 SignalR 与首个 HTTP 请求会并发取头部，
  /// 各自读到空值就会各生成一个 ID，先发出去的那个随后被覆盖。
  Future<String>? _pending;

  Future<String> value() => _pending ??= _resolve();

  Future<String> _resolve() async {
    final existing = await _readExisting();
    if (existing != null) return existing;
    final generated = _randomUuid();
    await _write(generated);
    return generated;
  }

  Future<String?> _readExisting() async {
    try {
      final stored = await _credentials.read(AuthCredentialKeys.visitorId);
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (_) {
      // 读失败不等于首次安装，宁可这次用临时值也不要覆盖已有标识。
      return _randomUuid();
    }
    return null;
  }

  Future<void> _write(String id) async {
    try {
      await _credentials.write(AuthCredentialKeys.visitorId, id);
    } catch (_) {}
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
