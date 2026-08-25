import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../image_cache.dart';
import 'html/reader_content_markup.dart';
import 'html/reader_content_style.dart';
import 'html_content.dart';
import 'image_preview.dart';

/// 正文图片的高度上限，翻页模式下由阅读器套在正文层与测量层之上。
///
/// 一页放不下的插图会被分页硬切成两半（后半页往往只剩一条），缩到一页内更好读。
/// 两层读的是同一个值，几何才对得上。
class ReaderImageBounds extends InheritedWidget {
  const ReaderImageBounds({
    super.key,
    required this.maxHeight,
    required super.child,
  });

  /// 一页的正文高度，已扣掉页面留白。
  final double maxHeight;

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderImageBounds>()
      ?.maxHeight;

  @override
  bool updateShouldNotify(ReaderImageBounds oldWidget) =>
      oldWidget.maxHeight != maxHeight;
}

/// 小说正文的 HTML 块渲染器。
///
/// 负责分页测量、正文额外样式、脚注链接和长按图片预览。
class ReaderHtmlBlock extends StatefulWidget {
  const ReaderHtmlBlock({
    super.key,
    required this.markup,
    required this.style,
    this.onFootnote,
    this.onTapUrl,
    this.onLayoutChanged,
    this.borderIllustrations = true,
    this.applyLineSpace = true,
    this.measureOnly = false,
  });

  final String markup;
  final ReaderContentStyle style;
  final ValueChanged<String>? onFootnote;
  final FutureOr<bool> Function(String url)? onTapUrl;
  final VoidCallback? onLayoutChanged;
  final bool borderIllustrations;
  final bool applyLineSpace;

  /// 只用于分页测量时，图片位置摆等尺寸的空盒子而不是真图：测量层只要几何，
  /// 建一份 [ContentImage] 就多一个图片组件与一条 `ImageStream` 监听。
  /// 尺寸未知的图仍会去取原始尺寸并回报，否则测量停在 2:3 占位上。
  final bool measureOnly;

  @override
  State<ReaderHtmlBlock> createState() => _ReaderHtmlBlockState();
}

class _ReaderHtmlBlockState extends State<ReaderHtmlBlock> {
  static final RegExp _spacedTextBlock = RegExp(
    r'^\s*<(?:p|h[1-6])\b',
    caseSensitive: false,
  );
  static const Set<String> _illustrationClasses = <String>{
    'illu',
    'illus',
    'duokan-image-single',
  };

  final Map<String, Size> _imageSizes = <String, Size>{};

  /// 图片回填尺寸的代数，作为 `HtmlWidget` 缓存树的失效条件。
  int _imageEpoch = 0;

  @override
  void didUpdateWidget(covariant ReaderHtmlBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markup != widget.markup) _imageSizes.clear();
  }

  /// 块级段间距判定按 markup 的实例缓存。
  String? _spacingSource;
  bool _hasSpacedTextBlock = false;

  bool get _spacedTextBlockPresent {
    final markup = widget.markup;
    if (!identical(_spacingSource, markup)) {
      _spacingSource = markup;
      _hasSpacedTextBlock = _spacedTextBlock.hasMatch(markup);
    }
    return _hasSpacedTextBlock;
  }

  /// 标题和正文都按段落级文本块处理，统一应用块后间距。
  double get _blockBottomSpacing =>
      widget.applyLineSpace &&
          widget.style.lineSpace > 0 &&
          _spacedTextBlockPresent
      ? widget.style.lineSpace
      : 0;

  @override
  Widget build(BuildContext context) {
    final content = _html(context);
    final spacing = _blockBottomSpacing;
    if (spacing <= 0) return content;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing),
      child: content,
    );
  }

  Widget _html(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return HtmlContentTheme(
      data: HtmlContentThemeData(
        textStyle: widget.style.textStyle.copyWith(color: color),
        linkColor: color,
        stylesBuilder: (element) => widget.style.stylesFor(
          tag: element.localName,
          classes: element.classes,
          // 只有 `<font size>` 需要读属性，其余标签不建表。
          attributes: element.localName == 'font'
              ? <String, String>{
                  for (final entry in element.attributes.entries)
                    entry.key.toString(): entry.value,
                }
              : const <String, String>{},
        ),
        widgetBuilder: (element) {
          if (element.localName == readerIndentElement) {
            return InlineCustomWidget(
              alignment: PlaceholderAlignment.bottom,
              child: SizedBox(width: widget.style.fontSize * 2),
            );
          }
          if (element.localName != 'img') return null;
          return _image(
            element.attributes['src'],
            element.parent?.localName,
            element.parent?.classes ?? const <String>{},
            element.parent?.text ?? '',
          );
        },
        onTapUrl: _onTapUrl,
        onErrorBuilder: (context, element, error) => const SizedBox.shrink(),
        onLoadingBuilder: (context, element, progress) =>
            const SizedBox.shrink(),
        buildAsync: false,
        enableCaching: true,
        removeImageLinks: false,
        enableDefaultImagePreview: false,
        rebuildTriggers: <Object?>[
          widget.style,
          widget.borderIllustrations,
          _imageEpoch,
        ],
      ),
      child: HtmlContent(html: widget.markup),
    );
  }

  Widget? _image(
    String? source,
    String? parentTag,
    Iterable<String> parentClasses,
    String siblingText,
  ) {
    final url = source == null ? null : resolvePreviewImageUrl(source);
    if (url == null) return const SizedBox.shrink();
    final metadata = contentImageMetadata(url);
    final block = parentTag == 'p' && siblingText.trim().isEmpty;
    final image = _ReaderBlockImage(
      url: url,
      size: _imageSizes[url] ?? metadata.size,
      reservedHeight: _blockBottomSpacing,
      blurHash: metadata.blurHash,
      bordered:
          widget.borderIllustrations &&
          parentClasses.any(_illustrationClasses.contains),
      inline: !block,
      measureOnly: widget.measureOnly,
      onResolved: _onImageResolved,
    );
    // 纯图片段落占一块；裸图片和带文字的段内图片保持行内语义。
    if (block) return image;
    return InlineCustomWidget(child: image);
  }

  void _onImageResolved(String url, Size size) {
    if (!mounted || _imageSizes[url] == size) return;
    setState(() {
      _imageSizes[url] = size;
      _imageEpoch++;
    });
    widget.onLayoutChanged?.call();
  }

  FutureOr<bool> _onTapUrl(String url) {
    final footnote = readerFootnoteIdFromUrl(url);
    final onFootnote = widget.onFootnote;
    if (footnote != null && onFootnote != null) {
      onFootnote(footnote);
      return true;
    }
    return widget.onTapUrl?.call(url) ?? false;
  }
}

/// 尺寸未知时先按插图常见的 2:3 占位，真尺寸回来后通知上层重新排版。
class _ReaderBlockImage extends StatefulWidget {
  const _ReaderBlockImage({
    required this.url,
    required this.size,
    required this.reservedHeight,
    required this.blurHash,
    required this.bordered,
    required this.inline,
    required this.measureOnly,
    required this.onResolved,
  });

  final String url;
  final Size? size;

  /// 同一块里图片之外还要占的高度，算高度上限时扣掉。
  final double reservedHeight;
  final String? blurHash;
  final bool bordered;
  final bool inline;
  final bool measureOnly;
  final void Function(String url, Size size) onResolved;

  @override
  State<_ReaderBlockImage> createState() => _ReaderBlockImageState();
}

class _ReaderBlockImageState extends State<_ReaderBlockImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    if (widget.size == null) _resolve();
  }

  @override
  void didUpdateWidget(covariant _ReaderBlockImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _detach();
    if (widget.size == null) _resolve();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    final url = widget.url;
    final stream = CachedNetworkImageProvider(
      url,
      cacheManager: appImageCacheManager,
    ).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, synchronousCall) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      info.dispose();
      // 缓存命中时回调可能发生在 build 期间，延后上报避免同步 setState。
      if (synchronousCall) {
        scheduleMicrotask(() {
          if (mounted) widget.onResolved(url, size);
        });
      } else {
        widget.onResolved(url, size);
      }
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? math.max(1.0, constraints.maxWidth)
            : 320.0;
        var width = size == null ? maxWidth : math.min(maxWidth, size.width);
        var height = size == null || size.width <= 0
            ? maxWidth * 3 / 2
            : width * size.height / size.width;
        // 翻页模式下高过一页的图等比缩进这一页，否则会被分页从中间切开。
        final bounds = ReaderImageBounds.maybeOf(context);
        if (bounds != null) {
          final limit = math.max(1.0, bounds - widget.reservedHeight);
          if (height > limit) {
            width *= limit / height;
            height = limit;
          }
        }
        // ContentImage 的外框就是这个 SizedBox，测量层换成空盒子几何完全一致。
        final image = widget.measureOnly
            ? SizedBox(width: width, height: height)
            : ContentImage(
                url: widget.url,
                width: width,
                height: height,
                blurHash: widget.blurHash,
                borderRadius: 3,
                bordered: widget.bordered,
                requestSizedVariant: widget.blurHash != null,
              );
        if (widget.inline) return image;
        // 块级图片缩窄之后居中摆放。
        return widget.bordered || width < maxWidth - 0.5
            ? Align(alignment: Alignment.topCenter, child: image)
            : image;
      },
    );
  }
}
