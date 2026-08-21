import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../data/settings/app_settings.dart';
import '../../../shared/cover_seed.dart';
import '../../../shared/image_cache.dart';
import '../../../shared/image_sizing.dart';
import '../../../shared/widgets/blurhash_image.dart';
import '../../../shared/widgets/book_image.dart';
import 'book_detail_hero.dart';

/// 拿封面的主色当种子色覆盖 [child] 的主题。取色是异步的，所以自己持有 State：
/// 结果回来才重建，期间沿用应用主题。
class CoverPaletteTheme extends StatefulWidget {
  const CoverPaletteTheme({
    super.key,
    required this.coverUrl,
    required this.blurHash,
    required this.settings,
    required this.child,
  });

  final String coverUrl;
  final String? blurHash;
  final AppSettings settings;
  final Widget child;

  @override
  State<CoverPaletteTheme> createState() => _CoverPaletteThemeState();
}

class _CoverPaletteThemeState extends State<CoverPaletteTheme> {
  String? _paletteKey;
  Color? _coverSeed;

  /// BlurHash 已经包含封面的低频色彩信息，优先用它取色，避免为主题额外下载原图。
  void _syncPalette() {
    if (!widget.settings.coverColorExtraction) return;
    final coverUrl = widget.coverUrl;
    final hash = widget.blurHash?.trim();
    final hasBlurHash = hash != null && hash.isNotEmpty;
    if (!hasBlurHash && coverUrl.isEmpty) return;

    final key = hasBlurHash ? 'blur:$hash' : 'url:$coverUrl';
    if (key == _paletteKey) return;
    _paletteKey = key;
    _coverSeed = null;

    // 取色本身只要 96×144，但刻意跟主封面要同一档：那张图整页反正都要下，
    // 复用它等于零额外请求，比单独要一张最小档更省。
    final ImageProvider<Object> provider;
    if (hasBlurHash) {
      provider = BlurHashImage(hash, decodingWidth: 32, decodingHeight: 48);
    } else {
      final sized = sizedImageUrl(
        coverUrl,
        logicalHeight: bookCoverDisplayHeight,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      provider = CachedNetworkImageProvider(
        sized,
        cacheKey: BookImage.cacheKeyFor(sized),
        cacheManager: appImageCacheManager,
      );
    }
    resolveCoverSeedColor(
          provider,
          size: hasBlurHash ? const Size(32, 48) : const Size(96, 144),
        )
        .then((color) {
          if (!mounted || _paletteKey != key) return;
          if (color == null) return;
          setState(() => _coverSeed = color);
        })
        .catchError((Object _) {
          // 取色失败沿用应用主题。
        });
  }

  ThemeData _theme(BuildContext context) {
    final base = Theme.of(context);
    final settings = widget.settings;
    final seed = settings.coverColorExtraction ? _coverSeed : null;
    if (seed == null) return base;
    final hex = seed.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    return buildAppTheme(
      brightness: base.brightness,
      settings: settings.copyWith(
        seedColorValue: '#${hex.toUpperCase()}',
        useSystemColor: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncPalette();
    return Theme(data: _theme(context), child: widget.child);
  }
}
