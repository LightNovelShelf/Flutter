import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'blurhash_image.dart';

import '../image_cache.dart';
import '../image_sizing.dart';

/// 站内图片统一入口（封面、漫画整页）：BlurHash 占位 → 网络图淡入；失败自动重试
/// 一次并提供手动重试。
///
/// 占位层始终铺在网络图下面，等网络图完全不透明才被盖住。交给
/// `CachedNetworkImage.placeholder` 的话，它会边淡入边把占位层淡出，中途两层
/// 都半透明，背景透上来就是一次可见的闪烁。
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
  });

  final String url;

  /// 图片在布局里占据的高度（逻辑像素）。必填：按 DPR 折算后取 256 的档位，作为
  /// `height` 查询参数向图床要对应尺寸的图。解码尺寸不再由客户端二次限制 ——
  /// 到手的字节已经是服务端缩好的。
  final double displayHeight;

  final String? blurHash;
  final BoxFit fit;
  final FilterQuality filterQuality;

  /// 图片自身的高宽比，只用来决定 BlurHash 的解码尺寸；默认按封面比例。
  final double aspectRatio;

  final Duration fadeInDuration;

  /// 没有 BlurHash 时画在底色上的图标；传 null 只留底色。
  final IconData? fallbackIcon;

  /// 自动重试也失败后的兜底 UI，默认是盖在占位层上的小重试按钮。
  final Widget Function(BuildContext context, VoidCallback retry)? errorBuilder;

  static const double _coverAspectRatio = 1.5;

  /// Android 用 C++ 查表解码，避免在 UI isolate 里逐像素计算余弦。16 像素宽仍能
  /// 覆盖 4×3 分量 hash 的有效频率。
  static const int blurHashWidth = 16;
  static const int _blurHashMaxHeight = 64;
  static const int _revealedCapacity = 256;

  /// 进程级已展示过的图片，命中后跳过淡入动画（滚回去、翻回去不再重播）。
  /// `LinkedHashSet` 保序，命中时重新插入即为 LRU。
  static final LinkedHashSet<String> _revealed = LinkedHashSet<String>();

  /// 缓存键剥掉 `placeholder` 与 `t`：两者都不影响图片字节，同一张图从不同接口拿到
  /// 的地址可能带不同参数（甚至没有），带进键里就会重复下载、重复占容量。
  static String cacheKeyFor(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final Map<String, String> query =
        Map<String, String>.of(uri.queryParameters)
          ..remove('placeholder')
          ..remove('t');
    // `replace(queryParameters: null)` 是「保持原查询」而不是清空，空查询只能自己构造；
    // 顺带把 fragment 丢掉。
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static void clearRevealCache() => _revealed.clear();

  @override
  State<BookImage> createState() => _BookImageState();
}

class _BookImageState extends State<BookImage> {
  int _attempt = 0;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant BookImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _attempt = 0;
      _failed = false;
    }
  }

  /// 记录已展示过的图片。放在帧后执行：build 期间不改全局状态。
  void _markRevealed(String cacheKey) {
    if (BookImage._revealed.contains(cacheKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final LinkedHashSet<String> revealed = BookImage._revealed;
      revealed.remove(cacheKey);
      revealed.add(cacheKey);
      while (revealed.length > BookImage._revealedCapacity) {
        revealed.remove(revealed.first);
      }
    });
  }

  /// ImageProvider 走 ImageCache，同一个 hash 只解一次；像素由本机查表解码。
  Widget _placeholder(BuildContext context) {
    final String? blurHash = widget.blurHash;
    final ColorScheme colors = Theme.of(context).colorScheme;
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
        // 占位层跟真图用同一个 fit，两层才不会错位。
        fit: widget.fit,
        gaplessPlayback: true,
        // 解码完成前铺容器底色，而不是包默认的蓝灰色。
        frameBuilder: (context, child, frame, _) => frame == null
            ? ColoredBox(color: colors.surfaceContainerHighest)
            : child,
      );
    }
    final IconData? icon = widget.fallbackIcon;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: icon == null
          ? null
          : Center(child: Icon(icon, size: 28, color: colors.onSurfaceVariant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return _placeholder(context);

    final int bucket = imageHeightBucketFor(
      widget.displayHeight,
      MediaQuery.devicePixelRatioOf(context),
    );
    final String url = withImageHeight(widget.url, bucket);
    // `cacheKeyFor` 只剥 `placeholder`/`t`，`height` 保留在键里 —— 每档一份缓存，
    // 正是 256 步进要的效果。
    final String cacheKey = BookImage.cacheKeyFor(url);
    final bool wasRevealed = BookImage._revealed.contains(cacheKey);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _placeholder(context),
        if (_failed)
          (widget.errorBuilder ?? _defaultErrorBuilder)(context, _retry)
        else
          CachedNetworkImage(
            key: ValueKey<String>('$cacheKey#$_attempt'),
            imageUrl: url,
            cacheKey: cacheKey,
            cacheManager: appImageCacheManager,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            fadeInDuration: wasRevealed ? Duration.zero : widget.fadeInDuration,
            // 占位层由外层 Stack 负责，这里不能再淡出一层，否则中途露底。
            fadeOutDuration: Duration.zero,
            placeholder: (context, _) => const SizedBox.expand(),
            imageBuilder: (context, provider) {
              _markRevealed(cacheKey);
              return Image(
                image: provider,
                fit: widget.fit,
                filterQuality: widget.filterQuality,
                width: double.infinity,
                height: double.infinity,
              );
            },
            errorWidget: (context, _, _) {
              // 第一次失败后自动重试一次，其余交给手动重试。
              final bool retryable = _attempt == 0;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (retryable) {
                  Future<void>.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && _attempt == 0) setState(() => _attempt = 1);
                  });
                } else if (!_failed) {
                  setState(() => _failed = true);
                }
              });
              return const SizedBox.expand();
            },
          ),
      ],
    );
  }

  void _retry() => setState(() {
    _failed = false;
    _attempt += 1;
  });

  static Widget _defaultErrorBuilder(
    BuildContext context,
    VoidCallback retry,
  ) => _RetryOverlay(onRetry: retry);
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
