import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

/// 封面加载：BlurHash 占位 → 网络图淡入；失败自动重试一次并提供手动重试。
///
/// 占位层始终铺在网络图下面，等网络图完全不透明才被盖住。交给
/// `CachedNetworkImage.placeholder` 的话，它会边淡入边把占位层淡出，中途两层
/// 都半透明，背景透上来就是一次可见的闪烁。
class BookCoverImage extends StatefulWidget {
  const BookCoverImage({
    super.key,
    required this.url,
    this.blurHash,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final String? blurHash;
  final BoxFit fit;
  final FilterQuality filterQuality;

  /// 列表缩略图应传入实际物理像素尺寸，避免把原始大图完整解码进内存。
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// 解码尺寸：够撑满一张封面缩略图，又不至于让解码变重。
  static const int _blurHashWidth = 32;
  static const int _blurHashHeight = 48;
  static const int _revealedCapacity = 256;

  /// 进程级已展示过的封面，命中后跳过淡入动画（滚回去不再重播）。
  /// `LinkedHashSet` 保序，命中时重新插入即为 LRU。
  static final LinkedHashSet<String> _revealed = LinkedHashSet<String>();

  static String cacheKeyFor(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final Map<String, String> query = Map<String, String>.of(
      uri.queryParameters,
    )..remove('placeholder');
    // `replace(fragment: '')` 会留下一个尾部 `#`，用 removeFragment 才干净。
    return uri
        .replace(queryParameters: query.isEmpty ? null : query)
        .removeFragment()
        .toString();
  }

  static void clearRevealCache() => _revealed.clear();

  @override
  State<BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<BookCoverImage> {
  int _attempt = 0;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant BookCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _attempt = 0;
      _failed = false;
    }
  }

  /// 记录已展示过的封面。放在帧后执行：build 期间不改全局状态。
  void _markRevealed(String cacheKey) {
    if (BookCoverImage._revealed.contains(cacheKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final LinkedHashSet<String> revealed = BookCoverImage._revealed;
      revealed.remove(cacheKey);
      revealed.add(cacheKey);
      while (revealed.length > BookCoverImage._revealedCapacity) {
        revealed.remove(revealed.first);
      }
    });
  }

  /// 用 `BlurHashImage` 而不是 `BlurHash` 组件：后者解码完成前先画一块
  /// `Colors.blueGrey`，且每次挂载都重新异步解码 —— 列表滚动时就是一片片色块闪。
  /// ImageProvider 走 ImageCache，同一个 hash 只解一次，重新挂载即时可画。
  Widget _placeholder(BuildContext context) {
    final String? blurHash = widget.blurHash;
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (blurHash != null && blurHash.isNotEmpty) {
      return Image(
        width: double.infinity,
        height: double.infinity,
        image: BlurHashImage(
          blurHash,
          decodingWidth: BookCoverImage._blurHashWidth,
          decodingHeight: BookCoverImage._blurHashHeight,
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // 解码完成前铺卡片底色，而不是包默认的蓝灰色。
        frameBuilder: (context, child, frame, _) => frame == null
            ? ColoredBox(color: colors.surfaceContainerHighest)
            : child,
      );
    }
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book_outlined,
          size: 28,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return _placeholder(context);

    final String cacheKey = BookCoverImage.cacheKeyFor(widget.url);
    final bool wasRevealed = BookCoverImage._revealed.contains(cacheKey);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _placeholder(context),
        if (_failed)
          _RetryOverlay(
            onRetry: () => setState(() {
              _failed = false;
              _attempt += 1;
            }),
          )
        else
          CachedNetworkImage(
            key: ValueKey<String>('$cacheKey#$_attempt'),
            imageUrl: widget.url,
            cacheKey: cacheKey,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: widget.memCacheWidth,
            memCacheHeight: widget.memCacheHeight,
            fadeInDuration: wasRevealed
                ? Duration.zero
                : const Duration(milliseconds: 200),
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
          tooltip: '重新加载封面',
        ),
      ),
    ],
  );
}
