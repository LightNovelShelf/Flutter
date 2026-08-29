import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'image_cache.dart';
import 'widgets/book_image.dart';

/// 相册和分享面板都靠扩展名判断类型，缓存文件的名字是 uuid、扩展名可能是
/// `.file`，所以导出前按内容重新落一份带扩展名的临时文件。
const Map<String, String> _mimeByExtension = <String, String>{
  'jpg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'avif': 'image/avif',
};

/// 分享图片。返回 null 表示已弹出分享面板（含用户取消），否则是可直接展示的失败原因。
Future<String?> shareImage(String url, {Rect? origin}) async {
  try {
    final File file = await _exportImageFile(url);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: _mimeOf(file.path))],
        sharePositionOrigin: origin,
      ),
    );
    return null;
  } catch (_) {
    return '分享失败，请稍后重试。';
  }
}

/// 专属目录/相册的名字，只有开启对应设置时才用。
const String _ownFolder = '轻书架';

/// 保存图片，返回可直接展示给用户的结果文案。
///
/// [ownFolder] 为真时存进「轻书架」相册（Android/Windows 是同名子目录），否则落在系统
/// 默认位置。相册要额外的照片图库权限（iOS 上是「完全访问」），所以默认关。
/// 没有相册概念的平台（Linux）退回下载目录。
Future<String> saveImage(String url, {required bool ownFolder}) async {
  try {
    final File file = await _exportImageFile(url);
    try {
      if (!await Gal.hasAccess(toAlbum: ownFolder) &&
          !await Gal.requestAccess(toAlbum: ownFolder)) {
        return '没有相册权限，请在系统设置里开启后重试。';
      }
      await Gal.putImage(file.path, album: ownFolder ? _ownFolder : null);
      return ownFolder ? '已保存到「$_ownFolder」相册' : '已保存到相册';
    } on MissingPluginException {
      final Directory? downloads = await getDownloadsDirectory();
      if (downloads == null) return '当前平台不支持保存图片。';
      final Directory target = ownFolder
          ? Directory('${downloads.path}/$_ownFolder')
          : downloads;
      await target.create(recursive: true);
      final File saved = await file.copy(
        '${target.path}/${_fileNameOf(file.path)}',
      );
      return '已保存到 ${saved.path}';
    }
  } on GalException catch (error) {
    return switch (error.type) {
      GalExceptionType.accessDenied => '没有相册权限，请在系统设置里开启后重试。',
      GalExceptionType.notEnoughSpace => '存储空间不足，无法保存。',
      GalExceptionType.notSupportedFormat => '相册不支持这张图片的格式。',
      GalExceptionType.unexpected => '保存失败，请稍后重试。',
    };
  } catch (_) {
    return '保存失败，请稍后重试。';
  }
}

/// 取一份带正确扩展名的本地文件：图片已在预览里显示过就直接命中缓存，不重新下载。
Future<File> _exportImageFile(String url) async {
  final File cached = await appImageCacheManager.getSingleFile(
    url,
    key: BookImage.cacheKeyFor(url),
  );
  final Uint8List bytes = await cached.readAsBytes();
  final String extension = _sniffExtension(bytes) ?? 'jpg';
  // 落在缓存目录旁边的固定子目录里，同名直接覆盖；清理交给系统的临时目录回收。
  final Directory dir = Directory('${cached.parent.path}/export');
  await dir.create(recursive: true);
  final File out = File('${dir.path}/${_baseName(url)}.$extension');
  await out.writeAsBytes(bytes, flush: true);
  return out;
}

String _fileNameOf(String path) =>
    path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);

String _mimeOf(String path) {
  final int dot = path.lastIndexOf('.');
  if (dot < 0) return 'image/jpeg';
  return _mimeByExtension[path.substring(dot + 1).toLowerCase()] ??
      'image/jpeg';
}

/// 分享面板会把文件名展示给用户，取地址里的文件名，去掉扩展名和非法字符。
String _baseName(String url) {
  final Uri? uri = Uri.tryParse(url);
  final String last = uri == null || uri.pathSegments.isEmpty
      ? ''
      : uri.pathSegments.last;
  final int dot = last.lastIndexOf('.');
  final String stem = dot > 0 ? last.substring(0, dot) : last;
  final String safe = stem.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
  return safe.isEmpty ? 'image' : safe;
}

String? _sniffExtension(Uint8List bytes) {
  bool match(int offset, List<int> magic) {
    if (bytes.length < offset + magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (match(0, <int>[0xFF, 0xD8, 0xFF])) return 'jpg';
  if (match(0, <int>[0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (match(0, <int>[0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (match(0, <int>[0x42, 0x4D])) return 'bmp';
  // RIFF....WEBP
  if (match(0, <int>[0x52, 0x49, 0x46, 0x46]) &&
      match(8, <int>[0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  // ISO-BMFF：前 4 字节是 box 长度，紧跟 ftyp 和具体品牌。
  if (match(4, <int>[0x66, 0x74, 0x79, 0x70])) {
    if (match(8, <int>[0x61, 0x76, 0x69, 0x66])) return 'avif';
    return 'heic';
  }
  return null;
}
