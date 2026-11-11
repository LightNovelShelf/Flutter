import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../data/settings/app_settings.dart';
import '../image_cache.dart';
import 'html/html_source.dart';
import 'html/reader_content_markup.dart';
import 'html/reader_content_style.dart';
import 'html_content.dart';
import 'image_preview.dart';

/// 正文图片的高度上限，翻页模式下由阅读器套在正文层与测量层之上。
///
/// 一页放不下的图像会被分页硬切成两半（后半页往往只剩一条），缩到一页内更好读。
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

/// “点击显示”模式下点开过的图像，按地址记。
///
/// 翻页模式不保留离屏页，正文块翻回来会整个重建，点开的状态要记在块外面。
class ReaderImageReveals extends ChangeNotifier {
  final Set<String> _urls = <String>{};

  bool contains(String url) => _urls.contains(url);

  void reveal(String url) {
    if (_urls.add(url)) notifyListeners();
  }
}

/// 阅读器把 [ReaderImageReveals] 挂在正文之上，一次阅读里点开过的图像翻回来、
/// 跨章回看都不必再点；没有挂的地方点开只在当前组件里有效。
class ReaderImageRevealScope extends InheritedNotifier<ReaderImageReveals> {
  const ReaderImageRevealScope({
    super.key,
    required ReaderImageReveals reveals,
    required super.child,
  }) : super(notifier: reveals);

  static ReaderImageReveals? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderImageRevealScope>()
      ?.notifier;
}

final RegExp _visibleVoidTagPattern = RegExp(
  r'<(?:hr|svg|video|audio)\b',
  caseSensitive: false,
);
// 与 `htmlImageTagPattern` 一样，属性值按引号整段跳过。
final RegExp _tagPattern = RegExp(r'''<(?:"[^"]*"|'[^']*'|[^<>'"])*>''');

// 不占地方的文字。`trim` 只管空白，零宽字符、方向标记与软连字符要另外去掉，
// 否则图片后面跟一个零宽空格，这一块在“不显示”模式下就会留一行空白。
final RegExp _invisibleTextPattern = RegExp(
  r'&nbsp;|[\u00AD\u200B-\u200F\u2060]',
);

/// 块里除了图片没有别的可见内容。`<br>` 不算：这种段落里的换行只是给图片留的空。
bool isReaderImageOnlyMarkup(String markup) {
  if (!htmlImageTagPattern.hasMatch(markup)) return false;
  final rest = removeHtmlImages(markup);
  if (_visibleVoidTagPattern.hasMatch(rest)) return false;
  return rest
      .replaceAll(_tagPattern, '')
      .replaceAll(_invisibleTextPattern, '')
      .trim()
      .isEmpty;
}

/// 小说正文的 HTML 块渲染器。
///
/// 负责分页测量、正文额外样式、脚注链接和长按图片预览，并按
/// [ReaderContentStyle.imageMode] 决定图像直接显示、点击显示还是不显示。
class ReaderHtmlBlock extends StatefulWidget {
  const ReaderHtmlBlock({
    super.key,
    required this.markup,
    required this.style,
    this.onFootnote,
    this.onTapUrl,
    this.onLayoutChanged,
    this.borderIllustrations = true,
    this.bottomSpacing = 0,
    this.measureOnly = false,
  });

  final String markup;
  final ReaderContentStyle style;
  final ValueChanged<String>? onFootnote;
  final FutureOr<bool> Function(String url)? onTapUrl;
  final VoidCallback? onLayoutChanged;
  final bool borderIllustrations;
  final double bottomSpacing;

  /// 只用于分页测量时，图片位置摆等尺寸的空盒子而不是真图：测量层只要几何，
  /// 建一份 [ContentImage] 就多一个图片组件与一条 `ImageStream` 监听。
  /// 尺寸未知的图仍会去取原始尺寸并回报，否则测量停在 2:3 占位上。
  final bool measureOnly;

  @override
  State<ReaderHtmlBlock> createState() => _ReaderHtmlBlockState();
}

class _ReaderHtmlBlockState extends State<ReaderHtmlBlock> {
  static const Set<String> _illustrationClasses = <String>{
    'illu',
    'illus',
    'duokan-image-single',
  };

  final Map<String, Size> _imageSizes = <String, Size>{};

  /// 图片回填尺寸的代数，作为 `HtmlWidget` 缓存树的失效条件。
  int _imageEpoch = 0;

  /// [isReaderImageOnlyMarkup] 的结果，只在“不显示”模式下用到时才算，按 markup 缓存。
  bool? _imageOnly;

  @override
  void didUpdateWidget(covariant ReaderHtmlBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markup != widget.markup) {
      _imageSizes.clear();
      _imageOnly = null;
    }
  }

  double get _blockBottomSpacing =>
      widget.bottomSpacing > 0 ? widget.bottomSpacing : 0;

  /// “不显示”模式下只有图像的块整块不占位，连同块底间距：`<p><img></p>` 也不留一行空白。
  bool get _hiddenEntirely =>
      widget.style.imageMode == ReaderImageMode.hide &&
      (_imageOnly ??= isReaderImageOnlyMarkup(widget.markup));

  @override
  Widget build(BuildContext context) {
    if (_hiddenEntirely) return const SizedBox.shrink();
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
            element.classes,
            element.parent?.classes ?? const <String>{},
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
          widget.bottomSpacing,
          _imageEpoch,
        ],
      ),
      child: HtmlContent(html: widget.markup),
    );
  }

  Widget? _image(
    String? source,
    Iterable<String> imageClasses,
    Iterable<String> parentClasses,
  ) {
    final url = source == null ? null : resolvePreviewImageUrl(source);
    if (url == null) return const SizedBox.shrink();
    final block = imageClasses.contains(htmlImageBlockClass);
    final mode = widget.style.imageMode;
    // 只剩图像的块在 build 里整块略去，走到这里的是图文混排的块：只抽掉图片本身，
    // 段内图片留一个零宽占位，前后文字照常接排。
    if (mode == ReaderImageMode.hide) {
      return block
          ? const SizedBox.shrink()
          : const InlineCustomWidget(child: SizedBox.shrink());
    }
    final metadata = contentImageMetadata(url);
    final imageSpacing = imageClasses.contains(htmlImageSpacingClass)
        ? widget.style.lineSpace
        : 0.0;
    final image = _ReaderBlockImage(
      url: url,
      size: _imageSizes[url] ?? metadata.size,
      reservedHeight: _blockBottomSpacing + imageSpacing,
      blurHash: metadata.blurHash,
      bordered:
          widget.borderIllustrations &&
          parentClasses.any(_illustrationClasses.contains),
      inline: !block,
      masked: mode == ReaderImageMode.tapToShow,
      measureOnly: widget.measureOnly,
      onResolved: _onImageResolved,
    );
    // 通用预处理标记图片块；段内图片没有标记，保持行内语义。
    if (block) {
      return imageSpacing > 0
          ? Padding(
              padding: EdgeInsets.only(bottom: imageSpacing),
              child: image,
            )
          : image;
    }
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

/// 尺寸未知时先按图像常见的 2:3 占位，真尺寸回来后通知上层重新排版。
class _ReaderBlockImage extends StatefulWidget {
  const _ReaderBlockImage({
    required this.url,
    required this.size,
    required this.reservedHeight,
    required this.blurHash,
    required this.bordered,
    required this.inline,
    required this.masked,
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

  /// “点击显示”模式：点开之前摆同尺寸的遮罩，几何与显示时完全一致，点开不必重排。
  /// 尺寸未知的图照样要取一次原图拿尺寸，否则点开后对不上测量层的几何。
  final bool masked;
  final bool measureOnly;
  final void Function(String url, Size size) onResolved;

  @override
  State<_ReaderBlockImage> createState() => _ReaderBlockImageState();
}

class _ReaderBlockImageState extends State<_ReaderBlockImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// 没有 [ReaderImageRevealScope] 时，点开的状态只记在这里。
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    if (widget.size == null) _resolve();
  }

  @override
  void didUpdateWidget(covariant _ReaderBlockImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _revealed = false;
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
        final reveals = widget.masked && !widget.measureOnly
            ? ReaderImageRevealScope.maybeOf(context)
            : null;
        final Widget image;
        if (widget.measureOnly) {
          image = SizedBox(width: width, height: height);
        } else if (widget.masked &&
            !_revealed &&
            !(reveals?.contains(widget.url) ?? false)) {
          image = _ReaderImageMask(
            width: width,
            height: height,
            onReveal: () {
              setState(() => _revealed = true);
              reveals?.reveal(widget.url);
            },
          );
        } else {
          image = ContentImage(
            url: widget.url,
            width: width,
            height: height,
            blurHash: widget.blurHash,
            borderRadius: 3,
            bordered: widget.bordered,
            requestSizedVariant: widget.blurHash != null,
          );
        }
        if (widget.inline) return image;
        // 块级图片缩窄之后居中摆放。
        return widget.bordered || width < maxWidth - 0.5
            ? Align(alignment: Alignment.topCenter, child: image)
            : image;
      },
    );
  }
}

/// “点击显示”模式下盖在图像位置上的遮罩，与图像同尺寸。
///
/// 只有中间的胶囊按钮接点击，其余地方照常交给翻页热区：整页图像不想看，点两侧照样翻过去。
/// 按钮带边框，看得见的范围就是能点的范围。太小的图摆不下按钮，才整块都可点。
class _ReaderImageMask extends StatelessWidget {
  const _ReaderImageMask({
    required this.width,
    required this.height,
    required this.onReveal,
  });

  final double width;
  final double height;
  final VoidCallback onReveal;

  /// 按钮的最小尺寸：高度与 48 的点击热区一致，加宽一些更好点中。
  static const Size _buttonSize = Size(160, 48);

  /// 按钮四周至少留这么宽的遮罩，留不出来就改成整块可点。
  static const double _buttonMargin = 16;

  static const String _label = '显示图像';

  @override
  Widget build(BuildContext context) {
    // 阅读器的正文色随背景走，遮罩跟着它取色，纸质、深色、自定义底色上都不突兀。
    final color =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    final roomy =
        width >= _buttonSize.width + _buttonMargin * 2 &&
        height >= _buttonSize.height + _buttonMargin * 2;
    final mask = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Center(
        // 只缩不放：大字号下按钮缩进遮罩里，小图上的图标也不会被撑大。
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: roomy
              ? OutlinedButton.icon(
                  onPressed: onReveal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color.withValues(alpha: 0.75),
                    side: BorderSide(color: color.withValues(alpha: 0.4)),
                    minimumSize: _buttonSize,
                  ),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text(_label),
                )
              : Icon(Icons.image_outlined, color: color.withValues(alpha: 0.6)),
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: roomy
          ? mask
          : Semantics(
              button: true,
              label: _label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onReveal,
                child: mask,
              ),
            ),
    );
  }
}
