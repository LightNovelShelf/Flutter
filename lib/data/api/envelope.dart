import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/network/api_error.dart';
import 'decode.dart';

/// 把信封的失败位转成 ApiError，SignalR 与裸 HTTP 两条链路共用。
void throwIfFailed(Map<String, dynamic> envelope, String fallbackMessage) {
  final success = envelope['Success'] ?? envelope['success'];
  if (success != false) return;
  final status = envelope['Status'] ?? envelope['status'];
  final message = envelope['Msg'] ?? envelope['msg'];
  final statusCode = status is num ? status.toInt() : null;
  throw ApiError(
    message is String && message.isNotEmpty ? message : fallbackMessage,
    statusCode == 401 || statusCode == -100
        ? ApiErrorCategory.auth
        : ApiErrorCategory.server,
    status: statusCode,
  );
}

/// 解开 SignalR 响应信封 `{success, status, msg, response}`，取出业务数据。
Object? unwrapSignalRResponse(Object? value) {
  final envelope = asRecordOrNull(value);
  if (envelope == null) {
    throw const ApiError('服务端返回了无效的响应。', ApiErrorCategory.server);
  }
  final success = envelope['Success'] ?? envelope['success'];
  if (success is! bool) {
    throw const ApiError('服务端返回了无效的响应。', ApiErrorCategory.server);
  }
  throwIfFailed(envelope, '请求失败。');
  return _decompress(envelope['Response'] ?? envelope['response']);
}

Object? _decompress(Object? value) {
  if (value is! String) return value;
  // `UseGzip` 后 byte[] 在 JSON 协议下是 base64 文本；普通字符串原样返回。
  late final Uint8List bytes;
  try {
    bytes = base64Decode(value);
  } catch (_) {
    return value;
  }
  if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return value;
  try {
    return _inflateJson(bytes);
  } catch (error) {
    throw ApiError('服务端返回了无效的压缩响应。', ApiErrorCategory.server, cause: error);
  }
}

/// 融合解码器，直接从 UTF-8 字节解析 JSON，不产生中间 String。
final Converter<List<int>, Object?> _utf8Json = const Utf8Decoder()
    .fuse<Object?>(const JsonDecoder());

Object? _inflateJson(Uint8List bytes) => _utf8Json.convert(gzip.decode(bytes));
