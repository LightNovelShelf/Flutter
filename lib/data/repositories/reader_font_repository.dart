import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show loadFontFromList;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// woff2.dart 的 @Native assetId 与 hook/build.dart 里的条目都写死了这个库路径，挪走要同步改原生构建，故留在 features 下。
import '../../features/reader/woff2.dart';
import '../api/endpoints.dart';

/// 章节字体缓存。正文字形被服务端混淆，需配套字体才能正确显示；WOFF2 先经
/// libwoff2 转成 TTF 再注册进 Flutter 引擎，正文按族名排版。
class ReaderFontRepository {
  const ReaderFontRepository();

  static const String _directoryName = 'reader-fonts';
  // 引擎的字体注册无法撤销，去重状态与实例无关，只能挂在进程上。
  static final Map<String, Future<String>> _inflight =
      <String, Future<String>>{};
  static final Set<String> _registered = <String>{};

  /// 相对地址按 API 源站补全；空地址表示该章节不用字体。
  static String? resolveFontUrl(String? fontUrl) {
    final value = fontUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return '${ServiceEndpoints.apiOrigin}${value.startsWith('/') ? '' : '/'}$value';
  }

  /// 返回已注册到 Flutter 引擎的字体族名。
  /// 无字体返回 null；下载、校验、转换或注册失败抛异常，调用方转错误态。
  Future<String?> loadFamily(
    String? fontUrl, {
    bool cacheEnabled = true,
    int cacheLimit = 30,
  }) {
    final url = resolveFontUrl(fontUrl);
    if (url == null) return Future<String?>.value();

    final digest = _digest(url);
    final family = 'chapter-font-$digest';
    if (_registered.contains(family)) return Future<String?>.value(family);

    final pending = _inflight[url];
    if (pending != null) return pending;
    // whenComplete 回调不能返回值，`Map.remove` 返回的正是当前 Future，
    // 回调等待自身会永久挂起。
    final request =
        _load(
          url,
          digest: digest,
          family: family,
          cacheEnabled: cacheEnabled,
          cacheLimit: cacheLimit,
        ).whenComplete(() {
          _inflight.remove(url);
        });
    _inflight[url] = request;
    return request;
  }

  static Future<String> _load(
    String url, {
    required String digest,
    required String family,
    required bool cacheEnabled,
    required int cacheLimit,
  }) async {
    final file = cacheEnabled ? await _cacheFile(digest) : null;
    if (file != null && file.existsSync()) {
      final cached = await file.readAsBytes();
      final prepared = await _prepare(cached);
      if (_isEngineFont(prepared)) {
        // 旧缓存可能是 WOFF2 原件，回写转换结果避免下次重复解码。
        if (!identical(prepared, cached)) {
          await file.writeAsBytes(prepared, flush: true);
        }
        return _register(family, prepared);
      }
      await file.delete();
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '章节字体下载失败（${response.statusCode}）。',
        uri: Uri.parse(url),
      );
    }
    final bytes = await _prepare(response.bodyBytes);
    if (!_isEngineFont(bytes)) throw const FormatException('章节字体格式无法识别。');

    if (file != null) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await _trim(file.parent, cacheLimit);
    }
    return _register(family, bytes);
  }

  static Future<String> _register(String family, Uint8List bytes) async {
    await loadFontFromList(bytes, fontFamily: family);
    _registered.add(family);
    return family;
  }

  static String _digest(String url) => md5.convert(utf8.encode(url)).toString();

  static Future<File> _cacheFile(String digest) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/$_directoryName',
    );
    return File('${directory.path}/$digest.font');
  }

  /// 超出上限时按最后修改时间淘汰最旧的字体文件。
  static Future<void> _trim(Directory directory, int limit) async {
    if (limit <= 0) return;
    final files = directory.listSync().whereType<File>().toList()
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

  static Future<Uint8List> _prepare(Uint8List bytes) {
    if (_fontMime(bytes) != 'font/woff2') {
      return Future<Uint8List>.value(bytes);
    }
    return Isolate.run(() => decodeWoff2(bytes));
  }

  /// WOFF1 没有解码路径，与无法识别的魔数一样视为不可用字体。
  static bool _isEngineFont(List<int> bytes) => switch (_fontMime(bytes)) {
    'font/ttf' || 'font/otf' => true,
    _ => false,
  };

  /// 用魔数判断字体类型，避免把 HTML 错误页当成字体注册。
  static String? _fontMime(List<int> bytes) {
    if (bytes.length < 4) return null;
    final magic =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return switch (magic) {
      0x774F4632 => 'font/woff2',
      0x774F4646 => 'font/woff',
      0x4F54544F => 'font/otf',
      0x00010000 || 0x74727565 => 'font/ttf',
      _ => null,
    };
  }
}
