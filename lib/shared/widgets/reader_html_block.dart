import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../image_cache.dart';
import 'html/reader_content_markup.dart';
import 'html/reader_content_style.dart';
import 'image_preview.dart';

/// 小说阅读器与社区正文共用的 HTML 块渲染器。
///
/// 调用方决定滚动容器、排版预设与图片预览手势，本组件负责正文样式、图片占位、BlurHash 和尺寸回填。
class ReaderHtmlBlock extends StatefulWidget {
  const ReaderHtmlBlock({
    super.key,
    required this.markup,
    required this.style,
    this.onFootnote,
    this.onTapUrl,
    this.onLayoutChanged,
    this.borderIllustrations = true,
    this.imageBottomSpacing = 6,
    this.imagePreviewTrigger = ImagePreviewTrigger.longPress,
    this.applyParagraphSpacing = true,
    this.measureOnly = false,
  });

  final String markup;
  final ReaderContentStyle style;
  final ValueChanged<String>? onFootnote;
  final FutureOr<bool> Function(String url)? onTapUrl;
  final VoidCallback? onLayoutChanged;
  final bool borderIllustrations;
  final double imageBottomSpacing;
  final ImagePreviewTrigger imagePreviewTrigger;
  final bool applyParagraphSpacing;

  /// 只用于分页测量时，图片位置摆等尺寸的空盒子而不是真图：测量层只要几何，
  /// 建一份 [ContentImage] 就多一个图片组件与一条 `ImageStream` 监听。
  /// 尺寸未知的图仍会去取原始尺寸并回报，否则测量停在 2:3 占位上。
  final bool measureOnly;

  @override
  State<ReaderHtmlBlock> createState() => _ReaderHtmlBlockState();
}

class _ReaderHtmlBlockState extends State<ReaderHtmlBlock> {
  static final RegExp _linkedImage = RegExp(
    r'''<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>\s*(<img\b[^>]*>)\s*</a>''',
    caseSensitive: false,
  );
  static final RegExp _paragraphBlock = RegExp(
    r'^\s*<p\b',
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

  /// 点按预览要摘掉图片外的链接，摘的结果按 markup 缓存，别每次 build 重跑正则。
  String? _strippedMarkup;

  @override
  void didUpdateWidget(covariant ReaderHtmlBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markup != widget.markup) {
      _imageSizes.clear();
      _strippedMarkup = null;
    }
  }

  /// 点按预览时，包在图片外的链接会先吃掉点按，渲染前摘掉链接只留图片。
  bool get _previewOnTap =>
      widget.imagePreviewTrigger == ImagePreviewTrigger.tap;

  String get _markup {
    if (!_previewOnTap) return widget.markup;
    return _strippedMarkup ??= widget.markup.replaceAllMapped(
      _linkedImage,
      (match) => match.group(4) ?? '',
    );
  }

  bool _isImageLink(String url) {
    if (!_previewOnTap) return false;
    final target = Uri.tryParse(url);
    for (final match in _linkedImage.allMatches(widget.markup)) {
      final href = (match.group(1) ?? match.group(2) ?? match.group(3) ?? '')
          .replaceAll('&amp;', '&');
      if (href == url) return true;
      final candidate = Uri.tryParse(href);
      if (candidate == null || target == null) continue;
      final normalizedCandidate = candidate.path.isEmpty
          ? candidate.replace(path: '/')
          : candidate;
      final normalizedTarget = target.path.isEmpty
          ? target.replace(path: '/')
          : target;
      if (normalizedCandidate == normalizedTarget) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final content = _html();
    if (!widget.applyParagraphSpacing ||
        widget.style.paragraphSpacing <= 0 ||
        !_paragraphBlock.hasMatch(_markup)) {
      return content;
    }
    return Padding(
      padding: EdgeInsets.only(bottom: widget.style.paragraphSpacing),
      child: content,
    );
  }

  Widget _html() => HtmlWidget(
    _markup,
    // 超过一万字符时组件默认改成异步建树，那期间块高是 0，分页测量会把它当空块。
    buildAsync: false,
    // 同一块 markup 至少被解析两次（测量层与正文层各一份），跨页块在相邻两页还各来一次。
    enableCaching: true,
    rebuildTriggers: <Object?>[
      widget.style,
      widget.borderIllustrations,
      widget.imageBottomSpacing,
      widget.imagePreviewTrigger,
      _imageEpoch,
    ],
    renderMode: RenderMode.column,
    textStyle: widget.style.textStyle,
    customStylesBuilder: (element) => widget.style.stylesFor(
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
    customWidgetBuilder: (element) {
      if (element.localName == readerIndentElement) {
        return InlineCustomWidget(
          alignment: PlaceholderAlignment.bottom,
          child: SizedBox(width: widget.style.fontSize * 2),
        );
      }
      if (element.localName != 'img') return null;
      return _image(
        element.attributes['src'],
        element.classes,
        element.parent?.classes ?? const <String>{},
        element.parent?.text ?? '',
      );
    },
    onTapUrl: _onTapUrl,
    onErrorBuilder: (context, element, error) => const SizedBox.shrink(),
    onLoadingBuilder: (context, element, progress) => const SizedBox.shrink(),
  );

  Widget? _image(
    String? source,
    Iterable<String> classes,
    Iterable<String> parentClasses,
    String siblingText,
  ) {
    final url = source == null ? null : resolvePreviewImageUrl(source);
    if (url == null) return const SizedBox.shrink();
    final metadata = contentImageMetadata(url);
    final previewable = !classes.contains('no-preview');
    final image = _ReaderBlockImage(
      url: url,
      size: _imageSizes[url] ?? metadata.size,
      blurHash: metadata.blurHash,
      previewable: previewable,
      bordered:
          previewable &&
          widget.borderIllustrations &&
          parentClasses.any(_illustrationClasses.contains),
      trigger: widget.imagePreviewTrigger,
      measureOnly: widget.measureOnly,
      onResolved: _onImageResolved,
    );
    final spaced = previewable && widget.imageBottomSpacing > 0
        ? Padding(
            padding: EdgeInsets.only(bottom: widget.imageBottomSpacing),
            child: image,
          )
        : image;
    // 段落里夹着文字的图片必须留在行内，否则段落会被断开。
    return siblingText.trim().isEmpty
        ? spaced
        : InlineCustomWidget(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: spaced,
            ),
          );
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
    if (_isImageLink(url)) return true;
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
    required this.blurHash,
    required this.previewable,
    required this.bordered,
    required this.trigger,
    required this.measureOnly,
    required this.onResolved,
  });

  final String url;
  final Size? size;
  final String? blurHash;
  final bool previewable;
  final bool bordered;
  final ImagePreviewTrigger trigger;
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
    if (size == null && !widget.previewable) {
      final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 16;
      return Icon(
        Icons.image_outlined,
        size: fontSize,
        color: DefaultTextStyle.of(context).style.color,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? math.max(1.0, constraints.maxWidth)
            : 320.0;
        final width = size == null ? maxWidth : math.min(maxWidth, size.width);
        final height = size == null || size.width <= 0
            ? maxWidth * 3 / 2
            : width * size.height / size.width;
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
                previewable: widget.previewable,
                trigger: widget.trigger,
                requestSizedVariant: widget.blurHash != null,
              );
        return widget.bordered
            ? Align(alignment: Alignment.topCenter, child: image)
            : image;
      },
    );
  }
}
