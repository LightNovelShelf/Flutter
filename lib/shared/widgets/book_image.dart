import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'blurhash_image.dart';
import 'reveal_image.dart';

import '../image_cache.dart';
import '../image_sizing.dart';

/// 站内图片统一入口（封面、正文插图、漫画整页）：BlurHash 占位、网络图淡入，
/// 失败自动重试一次并提供手动重试。显示与淡入规则见 [RevealImage]。
class BookImage extends StatefulWidget {
  const BookImage({
    super.key,
    required this.url,
    required this.displayHeight,
    this.blurHash,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.aspectRatio = _coverAspectRatio,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.fallbackIcon = Icons.menu_book_outlined,
    this.errorBuilder,
    this.requestSizedVariant = true,
  });

  final String url;

  /// 图片在布局里占据的高度（逻辑像素）。按 DPR 折算后取 256 的档位，作为 `height` 查询参数
  /// 向图床索取对应尺寸的图。
  final double displayHeight;

  final String? blurHash;
  final BoxFit fit;
  final FilterQuality filterQuality;

  /// 图片自身的高宽比，只用来决定 BlurHash 的解码尺寸；默认按封面比例。
  final double aspectRatio;

  final Duration fadeInDuration;

  /// 没有 BlurHash 时画在底色上的图标；传 null 只留底色。
  final IconData? fallbackIcon;

  /// 是否向站内图床追加量化后的 `height` 参数。外站图片必须关闭。
  final bool requestSizedVariant;

  /// 自动重试也失败后的兜底 UI，默认是盖在占位层上的小重试按钮。
  final Widget Function(BuildContext context, VoidCallback retry)? errorBuilder;

  static const double _coverAspectRatio = 1.5;

  /// BlurHash 解码宽度（像素），16 足以覆盖 4×3 分量 hash 的有效频率。
  static const int blurHashWidth = 16;

  /// BlurHash 解码高度上限（像素），取 [decodeBlurHash] 的硬上限作兜底，实际高度按图片比例算。
  static const int _blurHashMaxHeight = 512;

  /// 缓存键剥掉 `placeholder` 与 `t`，两者不影响图片字节，同一张图从不同接口拿到的参数不同，
  /// 带进键里会重复下载。
  static String cacheKeyFor(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final Map<String, String> query =
        Map<String, String>.of(uri.queryParameters)
          ..remove('placeholder')
          ..remove('t');
    // `replace(queryParameters: null)` 表示保持原查询而不是清空，空查询只能自己构造，
    // 同时丢掉 fragment。
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 站内图片的 provider。显示、预取、取尺寸、导出都必须经由这里，
  /// 否则缓存键不一致，同一张图会被重复下载和解码。
  static CachedNetworkImageProvider providerFor(String url) =>
      CachedNetworkImageProvider(
        url,
        cacheKey: cacheKeyFor(url),
        cacheManager: appImageCacheManager,
      );

  @override
  State<BookImage> createState() => _BookImageState();
}

class _BookImageState extends State<BookImage> {
  CachedNetworkImageProvider? _provider;
  int _attempt = 0;
  bool _autoRetryScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant BookImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _attempt = 0;
      _autoRetryScheduled = false;
    }
    if (oldWidget.url != widget.url ||
        oldWidget.displayHeight != widget.displayHeight ||
        oldWidget.requestSizedVariant != widget.requestSizedVariant) {
      _resolve();
    }
  }

  /// 尺寸档地址和缓存键都要扫字符串、解析 URI，只在输入变化时重算；
  /// 结果相等时沿用旧实例，`Image` 不会重新解析。
  void _resolve() {
    if (widget.url.isEmpty) {
      _provider = null;
      return;
    }
    final String url = widget.requestSizedVariant
        ? sizedImageUrl(
            widget.url,
            logicalHeight: widget.displayHeight,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          )
        : widget.url;
    final CachedNetworkImageProvider provider = BookImage.providerFor(url);
    if (provider != _provider) _provider = provider;
  }

  /// ImageProvider 走 ImageCache，同一个 hash 只解码一次。
  Widget _placeholder(BuildContext context) {
    final String? blurHash = widget.blurHash;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget fallback = ColoredBox(color: colors.surfaceContainerHighest);
    if (blurHash != null && blurHash.isNotEmpty) {
      return Image(
        width: double.infinity,
        height: double.infinity,
        image: BlurHashImage(
          blurHash,
          decodingWidth: BookImage.blurHashWidth,
          decodingHeight: (BookImage.blurHashWidth * widget.aspectRatio)
              .round()
              .clamp(1, BookImage._blurHashMaxHeight),
        ),
        // 必须 fill：解码宽度只有 16，高度取整后比例是 1/16 的台阶，用真图的 fit 会按这个
        // 量化比例留出信箱边，占位层比真图窄或矮几个像素。
        fit: BoxFit.fill,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    final IconData? icon = widget.fallbackIcon;
    if (icon == null) return fallback;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 28, color: colors.onSurfaceVariant),
      ),
    );
  }

  /// 第一次失败后自动重试一次，期间保持占位层；之后交给手动重试。
  Widget _error(BuildContext context, Object error) {
    if (_attempt == 0) {
      if (!_autoRetryScheduled) {
        _autoRetryScheduled = true;
        final CachedNetworkImageProvider? failed = _provider;
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _attempt == 0 && _provider == failed) _retry();
        });
      }
      return _placeholder(context);
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _placeholder(context),
        (widget.errorBuilder ?? _defaultErrorBuilder)(context, _retry),
      ],
    );
  }

  void _retry() {
    final CachedNetworkImageProvider? provider = _provider;
    if (provider != null) PaintingBinding.instance.imageCache.evict(provider);
    setState(() => _attempt += 1);
  }

  static Widget _defaultErrorBuilder(
    BuildContext context,
    VoidCallback retry,
  ) => _RetryOverlay(onRetry: retry);

  @override
  Widget build(BuildContext context) {
    final CachedNetworkImageProvider? provider = _provider;
    if (provider == null) return _placeholder(context);
    return RevealImage(
      // 重试必须换掉 Image 的 State，才会重新解析同一个 provider。
      key: ValueKey<int>(_attempt),
      image: provider,
      revealKey: provider.cacheKey,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      fadeInDuration: widget.fadeInDuration,
      placeholder: _placeholder,
      errorBuilder: _error,
    );
  }
}

class _RetryOverlay extends StatelessWidget {
  const _RetryOverlay({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      const ColoredBox(color: Color(0x26000000)),
      Center(
        child: IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.image_not_supported_outlined),
          color: Colors.white70,
          iconSize: 26,
          tooltip: '重新加载',
        ),
      ),
    ],
  );
}
