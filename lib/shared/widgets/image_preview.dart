import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:photo_view/photo_view.dart';

import '../../data/api/endpoints.dart';

/// 取组件当前在屏幕上的矩形，作为预览动画的起点/终点。
Rect? globalRectOf(BuildContext context) {
  final object = context.findRenderObject();
  if (object is! RenderBox || !object.hasSize || !object.attached) return null;
  return object.localToGlobal(Offset.zero) & object.size;
}

/// 正文里的图片地址常是站内相对路径，预览前补全成绝对地址。
String? resolvePreviewImageUrl(String source) {
  final trimmed = source.replaceAll('&amp;', '&').trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.hasScheme) return uri.scheme == 'data' ? null : uri.toString();
  return Uri.parse(ServiceEndpoints.apiOrigin).resolveUri(uri).toString();
}

/// `HtmlWidget.onTapImage`：正文（帖子 / 简介 / 公告）里的图片点开全屏预览。
///
/// 这里拿不到被点图片的 RenderBox，只能用居中的淡入淡出过渡。
void previewHtmlImage(BuildContext context, ImageMetadata metadata) {
  for (final source in metadata.sources) {
    final url = resolvePreviewImageUrl(source.url);
    if (url == null) continue;
    unawaited(showImagePreview(context, url: url));
    return;
  }
}

/// 预览的变换层：进入/退出/下拉的位移与缩放都落在它身上。
const Key imagePreviewTransformKey = Key('image-preview-transform');

/// 全屏图片预览：从来源位置放大进入，退出时缩回原位；可捏合缩放、下拉关闭。
///
/// [sourceRect] 是来源缩略图在屏幕上的矩形（[globalRectOf]）。缺省时退化成
/// 居中的淡入淡出＋轻微缩放，仍然有过渡，不会像直接切页那样生硬。
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

  /// 下拉超过这个距离（或够快）就关闭，未达到则弹回。
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

  /// 松手后把拖拽位移弹回原位。
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
        _drag.dy.abs() >= _ImagePreview._dismissDistance || velocity.abs() > 700;
    if (dismissed) {
      Navigator.of(context).pop();
      return;
    }
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  /// 进入时的缩放起点：贴住来源缩略图的尺寸。
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
          imageProvider: CachedNetworkImageProvider(widget.url),
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 6,
          onTapUp: (context, _, _) => Navigator.of(context).pop(),
          loadingBuilder: (context, _) =>
              const Center(child: CircularProgressIndicator(color: Colors.white)),
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
        final dragProgress = (_drag.distance / (_ImagePreview._dismissDistance * 2))
            .clamp(0.0, 1.0);
        return ColoredBox(
          color: Colors.black.withValues(
            alpha: 0.96 * progress * (1 - 0.55 * dragProgress),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Opacity(
                  opacity: (progress * (1 - 0.35 * dragProgress)).clamp(0.0, 1.0),
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
