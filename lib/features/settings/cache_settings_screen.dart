import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';
import '../../shared/image_cache.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/book_image.dart';
import '../../shared/widgets/settings_rows.dart';

/// 阅读器下载并转换后的字体存放目录。
const String readerFontCacheDirectoryName = 'reader-fonts';

/// 缓存开关、字体缓存上限与两个清理动作。
class CacheSettingsScreen extends ConsumerStatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  ConsumerState<CacheSettingsScreen> createState() =>
      _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends ConsumerState<CacheSettingsScreen> {
  bool _clearingImages = false;
  bool _clearingFonts = false;

  Future<void> _clearImageCache() async {
    if (_clearingImages) return;
    _clearingImages = true;
    try {
      BookImage.clearRevealCache();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await appImageCacheManager.emptyCache();
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: '图片缓存已清除',
        message: '已删除下载的图片和解码后的 BlurHash 占位图。',
      );
    } catch (_) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: '无法清除图片缓存',
        message: '图片缓存无法清除，请重试。',
      );
    } finally {
      _clearingImages = false;
    }
  }

  Future<void> _clearFontCache() async {
    if (_clearingFonts) return;
    _clearingFonts = true;
    try {
      final removed = await _removeReaderFontCache();
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: '阅读字体缓存已清除',
        message: removed == 0 ? '没有可清除的阅读字体缓存。' : '已删除 $removed 个字体缓存文件。',
      );
    } catch (_) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: '无法清除阅读字体缓存',
        message: '字体缓存无法清除，请重试。',
      );
    } finally {
      _clearingFonts = false;
    }
  }

  /// 删除阅读字体缓存目录，返回删除的文件数量。
  Future<int> _removeReaderFontCache() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory(
      '${temporary.path}${Platform.pathSeparator}$readerFontCacheDirectoryName',
    );
    if (!directory.existsSync()) return 0;
    var removed = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) removed += 1;
    }
    await directory.delete(recursive: true);
    return removed;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('缓存')),
      body: SettingsList(
        children: <Widget>[
          SettingsSection(
            title: '本地缓存',
            children: <Widget>[
              SettingsToggleRow(
                title: '书籍详情缓存',
                description: '在此设备上保留最近打开的书籍详情',
                icon: Icons.article_outlined,
                value: settings.bookDetailCacheEnabled,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(bookDetailCacheEnabled: value),
                ),
              ),
              SettingsToggleRow(
                title: '字体缓存',
                description: '复用已下载的字体元数据和文件',
                icon: Icons.font_download_outlined,
                value: settings.fontCacheEnabled,
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(fontCacheEnabled: value),
                ),
              ),
              SettingsSliderRow(
                title: '字体缓存上限',
                description: '缓存字体记录的最大数量',
                icon: Icons.storage_outlined,
                value: settings.fontCacheLimit.toDouble(),
                min: 10,
                max: 60,
                divisions: 50,
                format: (value) => '${value.round()} 本',
                onChanged: (value) => controller.update(
                  (settings) => settings.copyWith(fontCacheLimit: value.round()),
                ),
              ),
              SettingsRow(
                title: '清除图片缓存',
                description: '删除已下载图片和已解码的 BlurHash 占位图',
                icon: Icons.image_not_supported_outlined,
                onTap: _clearImageCache,
              ),
              SettingsRow(
                title: '清除阅读字体缓存',
                description: '删除已下载和转换的章节字体',
                icon: Icons.text_fields,
                onTap: _clearFontCache,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
