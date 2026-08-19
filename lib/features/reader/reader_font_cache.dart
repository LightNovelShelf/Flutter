import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../data/api/endpoints.dart';

/// 正文字形被混淆过，只有配套的 WOFF2 才认得。Flutter 的 `FontLoader` 不吃 WOFF2，
/// 字体只能以 `data:` URL 注入 WebView 的 `@font-face`。
class ReaderFontCache {
  const ReaderFontCache._();

  static const String _directoryName = 'reader-fonts';
  static final Map<String, Future<String>> _inflight = <String, Future<String>>{};

  /// 相对地址按 API 源站补全；空地址表示该章节不用字体。
  static String? resolveFontUrl(String? fontUrl) {
    final value = fontUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return '${ServiceEndpoints.apiOrigin}${value.startsWith('/') ? '' : '/'}$value';
  }

  /// 返回可直接写进 `@font-face` 的 `data:font/woff2;base64,...`。
  /// 无字体返回 null；下载或校验失败抛异常，调用方转错误态。
  static Future<String?> load(
    String? fontUrl, {
    bool cacheEnabled = true,
    int cacheLimit = 30,
  }) {
    final url = resolveFontUrl(fontUrl);
    if (url == null) return Future<String?>.value();

    final pending = _inflight[url];
    if (pending != null) return pending;
    // 回调不能返回值：`Map.remove` 会把正在完成的那个 Future 返回出去，
    // `whenComplete` 就会等自己，永久挂起。
    final request = _load(url, cacheEnabled: cacheEnabled, cacheLimit: cacheLimit)
        .whenComplete(() {
      _inflight.remove(url);
    });
    _inflight[url] = request;
    return request;
  }

  static Future<String> _load(
    String url, {
    required bool cacheEnabled,
    required int cacheLimit,
  }) async {
    final file = cacheEnabled ? await _cacheFile(url) : null;
    if (file != null && file.existsSync()) {
      final bytes = await file.readAsBytes();
      final mime = _fontMime(bytes);
      if (mime != null) {
        final url = _dataUrl(mime, bytes);
        return url;
      }
      await file.delete();
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('章节字体下载失败（${response.statusCode}）。', uri: Uri.parse(url));
    }
    final bytes = response.bodyBytes;
    final mime = _fontMime(bytes);
    if (mime == null) throw const FormatException('章节字体格式无法识别。');

    if (file != null) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await _trim(file.parent, cacheLimit);
    }
    return _dataUrl(mime, bytes);
  }

  static Future<File> _cacheFile(String url) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/$_directoryName',
    );
    final digest = md5.convert(utf8.encode(url)).toString();
    return File('${directory.path}/$digest.font');
  }

  /// 超出上限时按最后修改时间淘汰最旧的字体文件。
  static Future<void> _trim(Directory directory, int limit) async {
    if (limit <= 0) return;
    final files = directory
        .listSync()
        .whereType<File>()
        .toList()
      ..sort(
        (left, right) =>
            left.statSync().modified.compareTo(right.statSync().modified),
      );
    for (var index = 0; index < files.length - limit; index++) {
      try {
        await files[index].delete();
      } catch (_) {
        // 缓存清理失败不影响阅读。
      }
    }
  }

  static String _dataUrl(String mime, List<int> bytes) =>
      'data:$mime;base64,${base64Encode(bytes)}';

  /// 用魔数判断字体类型，避免把 HTML 错误页当成字体注入。
  static String? _fontMime(List<int> bytes) {
    if (bytes.length < 4) return null;
    final magic = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return switch (magic) {
      0x774F4632 => 'font/woff2',
      0x774F4646 => 'font/woff',
      0x4F54544F => 'font/otf',
      0x00010000 || 0x74727565 => 'font/ttf',
      _ => null,
    };
  }
}
