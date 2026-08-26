import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:photo_view/photo_view.dart';

import '../../data/api/endpoints.dart';
import '../../data/api/decode.dart';
import 'book_image.dart';
import '../image_cache.dart';
import '../image_sizing.dart';

/// 取组件当前在屏幕上的矩形，作为预览动画的起点/终点。
Rect? globalRectOf(BuildContext context) {
  final object = context.findRenderObject();
  if (object is! RenderBox || !object.hasSize || !object.attached) return null;
  return object.localToGlobal(Offset.zero) & object.size;
}

/// 图片地址附带的 BlurHash 与原始尺寸，用于在网络请求完成前占位。
typedef ContentImageMetadata = ({String? blurHash, Size? size});

ContentImageMetadata contentImageMetadata(String url) {
  final size = extractImageSize(url);
  return (
    blurHash: extractBlurHashPlaceholder(url),
    size: size == null
        ? null
        : Size(size.width.toDouble(), size.height.toDouble()),
  );
}

/// 正文里的图片地址常是站内相对路径，预览前补全成绝对地址。
String? resolvePreviewImageUrl(String source, {Uri? baseUrl}) {
  final trimmed = source.replaceAll('&amp;', '&').trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.hasScheme) return uri.scheme == 'data' ? null : uri.toString();
  return (baseUrl ?? Uri.parse(ServiceEndpoints.apiOrigin))
      .resolveUri(uri)
      .toString();
}

/// 简介、公告和脚注等轻量 HTML 的图片点击预览。
void previewHtmlImage(BuildContext context, ImageMetadata metadata) {
  for (final source in metadata.sources) {
    final url = resolvePreviewImageUrl(source.url);
    if (url == null) continue;
    unawaited(showImagePreview(context, url: url));
    return;
  }
}

/// 图片预览的触发手势。
enum ImagePreviewTrigger { tap, longPress }

/// 小说、漫画和富文本共用的内容图片：预留尺寸、BlurHash、加载和预览。
class ContentImage extends StatelessWidget {
  const ContentImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.blurHash,
    this.fit = BoxFit.contain,
    this.fadeInDuration = const Duration(milliseconds: 120),
    this.fallbackIcon,
    this.errorBuilder,
    this.borderRadius = 0,
    this.bordered = false,
    this.trigger = ImagePreviewTrigger.longPress,
    this.requestSizedVariant = true,
    this.onPreview,
  });

  final String url;
  final double width;
  final double height;
  final String? blurHash;
  final BoxFit fit;
  final Duration fadeInDuration;
  final IconData? fallbackIcon;
  final Widget Function(BuildContext context, VoidCallback retry)? errorBuilder;
  final double borderRadius;
  final bool bordered;
  final ImagePreviewTrigger trigger;
  final bool requestSizedVariant;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    // 预览与显示共用这个地址：同一个尺寸档就是同一份缓存，展开时不再重新下载。
    final requestUrl = requestSizedVariant
        ? sizedImageUrl(
            url,
            logicalHeight: height,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          )
        : url;
    Widget image = SizedBox(
      width: width,
      height: height,
      child: BookImage(
        url: requestUrl,
        displayHeight: height,
        blurHash: blurHash,
        fit: fit,
        aspectRatio: height / width,
        fadeInDuration: fadeInDuration,
        fallbackIcon: fallbackIcon,
        errorBuilder: errorBuilder,
        requestSizedVariant: false,
      ),
    );
    if (borderRadius > 0) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: image,
      );
    }
    if (bordered) {
      image = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: image,
      );
    }
    return Builder(
      builder: (sourceContext) {
        void preview() {
          final onPreview = this.onPreview;
          if (onPreview != null) {
            onPreview();
            return;
          }
          unawaited(
            showImagePreview(
              sourceContext,
              url: requestUrl,
              sourceRect: globalRectOf(sourceContext),
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: trigger == ImagePreviewTrigger.tap ? preview : null,
          onLongPress: trigger == ImagePreviewTrigger.longPress
              ? preview
              : null,
          child: image,
        );
      },
    );
  }
}

/// 预览的变换层，承载进入、退出、下拉的位移与缩放。
const Key imagePreviewTransformKey = Key('image-preview-transform');

/// 全屏图片预览：从来源位置放大进入，退出时缩回原位，支持捏合缩放与下拉关闭。
///
/// [sourceRect] 是来源缩略图在屏幕上的矩形（[globalRectOf]），缺省时改用居中的淡入淡出加轻微缩放。
Future<void> showImagePreview(
  BuildContext context, {
  required String url,
  Rect? sourceRect,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, _) =>
        _ImagePreview(url: url, sourceRect: sourceRect, animation: animation),
  ),
);

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({
    required this.url,
    required this.sourceRect,
    required this.animation,
  });

  final String url;
  final Rect? sourceRect;
  final Animation<double> animation;

  /// 下拉关闭的位移阈值（逻辑像素），未达到则弹回。
  static const double _dismissDistance = 120;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview>
    with SingleTickerProviderStateMixin {
  late final Animation<double> _entry = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// 松手后把拖拽位移弹回原位的控制器。
  late final AnimationController _settle = AnimationController(
    duration: const Duration(milliseconds: 220),
    vsync: this,
  )..addListener(_onSettle);
  late final Animation<double> _settleCurve = CurvedAnimation(
    parent: _settle,
    curve: Curves.easeOutCubic,
  );

  Offset _drag = Offset.zero;
  Offset _settleFrom = Offset.zero;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onSettle() {
    setState(() {
      _drag = Offset.lerp(_settleFrom, Offset.zero, _settleCurve.value)!;
    });
  }

  void _onDragStart(DragStartDetails _) {
    _settle.stop();
    _settleFrom = Offset.zero;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _drag += details.delta);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissed =
        _drag.dy.abs() >= _ImagePreview._dismissDistance ||
        velocity.abs() > 700;
    if (dismissed) {
      Navigator.of(context).pop();
      return;
    }
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  /// 进入动画的缩放起点，按来源缩略图与屏幕的尺寸比算。
  double _beginScale(Size screen) {
    final rect = widget.sourceRect;
    if (rect == null || rect.isEmpty || screen.isEmpty) return 0.92;
    return math
        .max(rect.width / screen.width, rect.height / screen.height)
        .clamp(0.05, 1.0);
  }

  Matrix4 _transform(Size screen, double progress, double dragProgress) {
    final center = Offset(screen.width / 2, screen.height / 2);
    final from = widget.sourceRect?.center ?? center;
    final scale =
        ui.lerpDouble(_beginScale(screen), 1, progress)! *
        (1 - 0.2 * dragProgress);
    final origin = Offset.lerp(from, center, progress)! + _drag;
    return Matrix4.translationValues(origin.dx, origin.dy, 0) *
        Matrix4.diagonal3Values(scale, scale, 1) *
        Matrix4.translationValues(-center.dx, -center.dy, 0);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final image = PhotoViewGestureDetectorScope(
      axis: Axis.vertical,
      child: GestureDetector(
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: PhotoView(
          // 缓存键与 BookImage 一致，来源图已经下载过时直接命中。
          imageProvider: CachedNetworkImageProvider(
            widget.url,
            cacheKey: BookImage.cacheKeyFor(widget.url),
            cacheManager: appImageCacheManager,
          ),
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 6,
          onTapUp: (context, _, _) => Navigator.of(context).pop(),
          loadingBuilder: (context, _) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorBuilder: (context, _, _) => const Center(
            child: Text(
              '图片加载失败',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) {
        final progress = _entry.value.clamp(0.0, 1.0);
        final dragProgress =
            (_drag.distance / (_ImagePreview._dismissDistance * 2)).clamp(
              0.0,
              1.0,
            );
        return ColoredBox(
          color: Colors.black.withValues(
            alpha: 0.96 * progress * (1 - 0.55 * dragProgress),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Opacity(
                  opacity: (progress * (1 - 0.35 * dragProgress)).clamp(
                    0.0,
                    1.0,
                  ),
                  child: Transform(
                    key: imagePreviewTransformKey,
                    transform: _transform(screen, progress, dragProgress),
                    child: child,
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 8,
                child: Opacity(
                  opacity: (progress * (1 - dragProgress)).clamp(0.0, 1.0),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    tooltip: '关闭',
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: image,
    );
  }
}
