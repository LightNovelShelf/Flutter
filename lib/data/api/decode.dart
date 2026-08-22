import '../../core/network/api_error.dart';

const String blurHashBase83 =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';

Map<String, dynamic> asRecord(Object? value, String name) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw ApiError('服务端返回了无效的 $name。', ApiErrorCategory.server);
}

Map<String, dynamic>? asRecordOrNull(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

/// 可选的嵌套对象，缺失时返回空表。
Map<String, dynamic> asRecordOrEmpty(Object? value) =>
    asRecordOrNull(value) ?? const <String, dynamic>{};

List<dynamic> asArray(Object? value, String name) {
  if (value is List) return value;
  throw ApiError('服务端返回了无效的 $name。', ApiErrorCategory.server);
}

String asString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  throw const ApiError('服务端返回了无效的文本字段。', ApiErrorCategory.server);
}

String asStringOrEmpty(Object? value) => value is String ? value : '';

String? asNullableString(Object? value) {
  if (value == null || value == '') return null;
  return asString(value);
}

num _asNum(Object? value) => value as num;

int asInt(Object? value, [int? fallback]) {
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  if (fallback != null) return fallback;
  throw const ApiError('服务端返回了无效的数字字段。', ApiErrorCategory.server);
}

int? asNullableInt(Object? value) => value == null ? null : asInt(value);

double asDouble(Object? value, [double? fallback]) {
  if (value is num && value.isFinite) return _asNum(value).toDouble();
  if (fallback != null) return fallback;
  throw const ApiError('服务端返回了无效的数字字段。', ApiErrorCategory.server);
}

bool asBool(Object? value, [bool? fallback]) {
  if (value is bool) return value;
  if (fallback != null) return fallback;
  throw const ApiError('服务端返回了无效的布尔字段。', ApiErrorCategory.server);
}

/// 服务端给 ISO8601 字符串，解析失败时回落到当前时间。
DateTime asDate(Object? value) {
  final text = asString(value);
  return DateTime.tryParse(text)?.toLocal() ?? DateTime.now();
}

DateTime? asNullableDate(Object? value) {
  if (value == null || value == '') return null;
  final text = value is String ? value : value.toString();
  return DateTime.tryParse(text)?.toLocal();
}

List<String> decodeStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().where((item) => item.isNotEmpty).toList();
}

List<int> decodeIntList(Object? value, String name) =>
    asArray(value, name).map(asInt).toList();

List<T> decodeOptionalList<T>(
  Object? value,
  String name,
  T Function(Object? item) decode,
) {
  if (value == null) return <T>[];
  return asArray(value, name).map(decode).toList();
}

/// 码位到 base83 数位的查表，非法字符为 -1。
final List<int> _base83Digits = () {
  final table = List<int>.filled(128, -1);
  for (var i = 0; i < blurHashBase83.length; i++) {
    table[blurHashBase83.codeUnitAt(i)] = i;
  }
  return table;
}();

int _base83DigitAt(String value, int index) {
  final code = value.codeUnitAt(index);
  return code < 128 ? _base83Digits[code] : -1;
}

/// 不是完整可用的 BlurHash 时返回 null。
String? normalizeBlurHash(Object? value) {
  if (value is! String || value.length < 6) return null;
  for (var i = 0; i < value.length; i++) {
    if (_base83DigitAt(value, i) < 0) return null;
  }
  final sizeFlag = _base83DigitAt(value, 0);
  final componentCount = (sizeFlag ~/ 9 + 1) * (sizeFlag % 9 + 1);
  return value.length == 4 + 2 * componentCount ? value : null;
}

class _RawQueryValue {
  const _RawQueryValue(
    this.rawValue,
    this.value,
    this.valueStart,
    this.valueEnd,
  );

  final String rawValue;
  final String value;
  final int valueStart;
  final int valueEnd;
}

/// 从原始 URL 文本里取查询值。封面 placeholder 含未转义的 base83 字符
/// （`+`、`#`），标准 URL 解析会破坏它们。
_RawQueryValue? _extractRawQueryValue(String rawUrl, String key) {
  final queryStart = rawUrl.indexOf('?');
  if (queryStart < 0) return null;
  var pairStart = queryStart + 1;
  while (pairStart <= rawUrl.length) {
    final pairEndCandidate = rawUrl.indexOf('&', pairStart);
    final pairEnd = pairEndCandidate < 0 ? rawUrl.length : pairEndCandidate;
    final separator = rawUrl.indexOf('=', pairStart);
    if (separator >= pairStart &&
        separator < pairEnd &&
        rawUrl.substring(pairStart, separator) == key) {
      final valueStart = separator + 1;
      final rawValue = rawUrl.substring(valueStart, pairEnd);
      final encoded = rawValue.replaceAll('+', '%2B');
      final value = encoded.replaceAllMapped(
        RegExp(r'%([0-9A-Fa-f]{2})'),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      );
      return _RawQueryValue(rawValue, value, valueStart, pairEnd);
    }
    if (pairEndCandidate < 0) break;
    pairStart = pairEnd + 1;
  }
  return null;
}

String? extractBlurHashPlaceholder(String value) =>
    normalizeBlurHash(_extractRawQueryValue(value, 'placeholder')?.value);

/// 图床地址上的 `size=<宽>x<高>`（像素），下载前就能按真实比例预留版面。
({int width, int height})? extractImageSize(String value) {
  final raw = _extractRawQueryValue(value, 'size')?.value;
  if (raw == null) return null;
  // 老封面串偶尔在末尾挂 fragment，`size` 是最后一个参数时会被带进来。
  final pair = raw.split('#').first;
  final separator = pair.indexOf('x');
  if (separator <= 0) return null;
  final width = int.tryParse(pair.substring(0, separator));
  final height = int.tryParse(pair.substring(separator + 1));
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

/// 修复旧封面 URL，未转义的 `#` 会把后续签名参数变成 fragment。
String normalizeCoverUrl(String value) {
  final placeholder = _extractRawQueryValue(value, 'placeholder');
  if (placeholder == null || !placeholder.rawValue.contains('#')) return value;
  final repaired = placeholder.rawValue.replaceAll('#', '%23');
  return value.substring(0, placeholder.valueStart) +
      repaired +
      value.substring(placeholder.valueEnd);
}

/// 计数字段钳到非负且有上限，服务端偶尔返回负数或超大值。
int asCount(Object? value, [int fallback = 0]) =>
    asInt(value, fallback).clamp(0, 1 << 30);

/// 封面原串同时含地址与 BlurHash 占位，一次解出两者。
({String url, String? placeholder}) decodeCover(Object? value) {
  final raw = asString(value);
  return (
    url: normalizeCoverUrl(raw),
    placeholder: extractBlurHashPlaceholder(raw),
  );
}
