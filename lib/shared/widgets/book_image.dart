import 'dart:async';
import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'blurhash_image.dart';

import '../image_cache.dart';
import '../image_sizing.dart';

/// 站内图片统一入口（封面、漫画整页）：BlurHash 占位、网络图淡入，失败自动重试一次并提供手动重试。
///
/// 占位层是 Stack 里网络图下方的一层，交给 `CachedNetworkImage.placeholder` 会边淡入边淡出、
/// 中途露底闪烁；淡入结束后摘掉，不再重复填充整块区域。
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
  static const int _revealedCapacity = 256;

  /// 进程级已展示过的图片，命中后跳过淡入动画。`LinkedHashSet` 保序，命中时重新插入即为 LRU。
  static final LinkedHashSet<String> _revealed = LinkedHashSet<String>();

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

  static void clearRevealCache() => _revealed.clear();

  @override
  State<BookImage> createState() => _BookImageState();
}

class _BookImageState extends State<BookImage> {
  int _attempt = 0;
  bool _failed = false;

  /// 真图淡入结束后置位，之后不再构建占位层。
  bool _placeholderHidden = false;
  Timer? _fadeTimer;
  bool _placeholderRestoreScheduled = false;

  /// build 期间只读的解析结果，只在 (url, displayHeight, DPR) 变化时重算。
  String _url = '';
  String _cacheKey = '';
  bool _wasRevealed = false;

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
      _failed = false;
      _fadeTimer?.cancel();
      _fadeTimer = null;
      _placeholderHidden = false;
    }
    if (oldWidget.url != widget.url ||
        oldWidget.displayHeight != widget.displayHeight ||
        oldWidget.requestSizedVariant != widget.requestSizedVariant) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  /// 取尺寸档地址和缓存键都要扫字符串、解析 URI，滚动时不能每帧重算。
  void _resolve() {
    if (widget.url.isEmpty) {
      _url = '';
      _cacheKey = '';
      _wasRevealed = false;
      return;
    }
    _url = widget.requestSizedVariant
        ? sizedImageUrl(
            widget.url,
            logicalHeight: widget.displayHeight,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          )
        : widget.url;
    // `height` 保留在缓存键里，每个尺寸档一份缓存。
    _cacheKey = BookImage.cacheKeyFor(_url);
    _wasRevealed = BookImage._revealed.contains(_cacheKey);
    // 已解码在内存里的图会在第一帧就画出来，占位层一帧都不必上。翻页、列表回滚都会
    // 把整棵子树重新挂载（PageView 不保留离屏页），照常走占位层就是一次 BlurHash 闪。
    _placeholderHidden = _isDecoded();
  }

  /// 解码结果是否还在 `ImageCache` 的常驻区里。键就是 `CachedNetworkImage` 内部用的
  /// provider，相等只看 (cacheKey, scale, maxWidth, maxHeight)，所以这里能造出同一个键。
  ///
  /// 只认 `keepAlive`：那是解码成功后才进的一档。`live` 在刚发起解析、甚至加载失败时
  /// 也可能为真，拿它当依据会在真图还没有的时候就把占位层摘掉。
  bool _isDecoded() => PaintingBinding.instance.imageCache
      .statusForKey(CachedNetworkImageProvider(_url, cacheKey: _cacheKey))
      .keepAlive;

  /// 路由覆盖期间 Image 会停止监听；解码缓存被驱逐后，返回列表会重新走占位回调。
  /// 先恢复外层占位，避免磁盘重新解码与淡入期间露出卡片底色。
  void _onImageLoading() {
    if (!_placeholderHidden || _placeholderRestoreScheduled) return;
    _placeholderRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeholderRestoreScheduled = false;
      if (mounted && _placeholderHidden) {
        setState(() => _placeholderHidden = false);
      }
    });
  }

  /// 真图出现：记录进程级已展示集合，并在淡入结束后摘掉占位层。
  ///
  /// 写集合放在帧后执行，避免在 build 期间修改全局状态。占位层要留满整个淡入过程，
  /// 提前摘会露底，多给一点余量等动画真正结束。
  void _onImageShown() {
    final String cacheKey = _cacheKey;
    if (!BookImage._revealed.contains(cacheKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final LinkedHashSet<String> revealed = BookImage._revealed;
        revealed.remove(cacheKey);
        revealed.add(cacheKey);
        while (revealed.length > BookImage._revealedCapacity) {
          revealed.remove(revealed.first);
        }
      });
    }
    if (_placeholderHidden || _fadeTimer != null) return;
    final Duration fade = _wasRevealed ? Duration.zero : widget.fadeInDuration;
    _fadeTimer = Timer(fade + const Duration(milliseconds: 50), () {
      _fadeTimer = null;
      if (mounted) setState(() => _placeholderHidden = true);
    });
  }

  /// ImageProvider 走 ImageCache，同一个 hash 只解码一次。
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
        // 必须 fill：解码宽度只有 16，高度取整后比例是 1/16 的台阶，用真图的 fit 会按这个
        // 量化比例留出信箱边，占位层比真图窄或矮几个像素。
        fit: BoxFit.fill,
        gaplessPlayback: true,
        // 解码完成前铺容器底色，否则显示包默认的蓝灰色。
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

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 真图不透明后占位层还画一整块 16px 拉满的图，白付一倍填充率，淡入结束就摘掉。
        if (!_placeholderHidden) _placeholder(context),
        if (_failed)
          (widget.errorBuilder ?? _defaultErrorBuilder)(context, _retry)
        else
          CachedNetworkImage(
            // 摘占位层会改 Stack 子节点位置，靠这个键认出同一张网络图、不重新加载。
            key: ValueKey<int>(_attempt),
            imageUrl: _url,
            cacheKey: _cacheKey,
            cacheManager: appImageCacheManager,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            fadeInDuration: _wasRevealed
                ? Duration.zero
                : widget.fadeInDuration,
            // 占位层由外层 Stack 负责，不能再淡出一层，否则中途露底。
            fadeOutDuration: Duration.zero,
            placeholder: (context, _) {
              _onImageLoading();
              return const SizedBox.expand();
            },
            imageBuilder: (context, provider) {
              _onImageShown();
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
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _placeholderHidden = false;
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
