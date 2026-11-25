import 'dart:collection';

import 'package:flutter/material.dart';

/// 带占位层的单张图片，所有状态只取自 [Image] 自己的出帧回调。
///
/// - 解码结果已在 `ImageCache`：首帧直接画真图，不建占位层、不淡入；
/// - 需要从磁盘或网络取：先画 [placeholder]，出帧后真图在占位层上淡入，
///   真图完全不透明后占位层再淡出并摘掉；
/// - 出帧时所在路由被遮住（`TickerMode` 关闭）或同一 [revealKey] 展示过：不淡入，
///   直接换成真图。淡入只受动画驱动，被遮住时动画暂停，占位层跟着保留。
///
/// 整体包在 [RepaintBoundary] 里：加载、淡入只重绘这一个图层，列表滚动时
/// 卡片的其它内容不受影响。
class RevealImage extends StatelessWidget {
  const RevealImage({
    super.key,
    required this.image,
    required this.placeholder,
    this.revealKey,
    this.errorBuilder,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.fadeInDuration = const Duration(milliseconds: 200),
  });

  final ImageProvider image;

  /// 真图出帧前（以及淡入期间）垫在下面的内容。
  final WidgetBuilder placeholder;

  /// 进程级“已展示过”的标识。缓存被驱逐后重新解码时据此跳过淡入。
  final Object? revealKey;

  /// 加载失败时的内容，默认显示占位层。
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  final BoxFit fit;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;

  static const int _revealedCapacity = 1024;

  /// `LinkedHashSet` 保序，命中时重新插入即为 LRU。
  static final LinkedHashSet<Object> _revealed = LinkedHashSet<Object>();

  static void clearRevealCache() => _revealed.clear();

  /// 记录一次展示，返回此前是否已展示过。
  static bool _markRevealed(Object? key) {
    if (key == null) return false;
    final bool seen = _revealed.remove(key);
    _revealed.add(key);
    if (_revealed.length > _revealedCapacity) _revealed.remove(_revealed.first);
    return seen;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Image(
      image: image,
      fit: fit,
      filterQuality: filterQuality,
      width: double.infinity,
      height: double.infinity,
      // 换源（尺寸档变化、缓存驱逐后重新解析）时旧图留在原位，直到新图出帧。
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, synchronous) => _RevealFrame(
        loaded: frame != null,
        synchronous: synchronous,
        revealKey: revealKey,
        fadeInDuration: fadeInDuration,
        placeholder: placeholder,
        child: child,
      ),
      errorBuilder: (context, error, _) =>
          errorBuilder?.call(context, error) ?? placeholder(context),
    ),
  );
}

class _RevealFrame extends StatefulWidget {
  const _RevealFrame({
    required this.loaded,
    required this.synchronous,
    required this.revealKey,
    required this.fadeInDuration,
    required this.placeholder,
    required this.child,
  });

  final bool loaded;
  final bool synchronous;
  final Object? revealKey;
  final Duration fadeInDuration;
  final WidgetBuilder placeholder;
  final Widget child;

  @override
  State<_RevealFrame> createState() => _RevealFrameState();
}

class _RevealFrameState extends State<_RevealFrame>
    with SingleTickerProviderStateMixin {
  /// 只在需要淡入时创建，之后保留到 dispose，用来判断是否已淡入过。
  AnimationController? _fade;
  late Animation<double> _imageOpacity;
  late Animation<double> _placeholderOpacity;
  late bool _showPlaceholder;

  @override
  void initState() {
    super.initState();
    _showPlaceholder = !widget.loaded;
    if (widget.loaded) RevealImage._markRevealed(widget.revealKey);
  }

  @override
  void didUpdateWidget(covariant _RevealFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.loaded) {
      _showPlaceholder = true;
      return;
    }
    if (oldWidget.loaded) return;

    final bool seen = RevealImage._markRevealed(widget.revealKey);
    final bool animate =
        !seen &&
        !widget.synchronous &&
        _fade == null &&
        widget.fadeInDuration > Duration.zero &&
        TickerMode.valuesOf(context).enabled;
    if (!animate) {
      _showPlaceholder = false;
      return;
    }
    // 前 2/3 真图淡入，后 1/3 占位层淡出：不透明图在占位层淡出前已盖满，不会露底；
    // 透明图的占位层也不会在最后一帧突然消失。
    final fade = AnimationController(
      vsync: this,
      duration: widget.fadeInDuration * 1.5,
    );
    _fade = fade;
    _imageOpacity = CurvedAnimation(
      parent: fade,
      curve: const Interval(0, 2 / 3, curve: Curves.easeOut),
    );
    _placeholderOpacity = ReverseAnimation(
      CurvedAnimation(parent: fade, curve: const Interval(2 / 3, 1)),
    );
    fade.addStatusListener((status) {
      if (status.isCompleted && mounted) {
        setState(() => _showPlaceholder = false);
      }
    });
    fade.forward();
  }

  @override
  void dispose() {
    _fade?.dispose();
    super.dispose();
  }

  /// 静止状态只有真图本身。`FadeTransition` 只要不透明度大于 0 就会单独占一个
  /// 透明度图层（不透明度为 1 也一样），只在淡入期间包上。
  @override
  Widget build(BuildContext context) {
    final AnimationController? fade = _fade;
    final bool fading = fade != null && fade.isAnimating;
    if (!_showPlaceholder && !fading) return widget.child;
    final Widget placeholder = widget.placeholder(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (_showPlaceholder)
          fading
              ? FadeTransition(opacity: _placeholderOpacity, child: placeholder)
              : placeholder,
        fading
            ? FadeTransition(opacity: _imageOpacity, child: widget.child)
            : widget.child,
      ],
    );
  }
}
