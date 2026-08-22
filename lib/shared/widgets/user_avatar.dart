import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../image_cache.dart';

/// 全站唯一的圆形头像：无地址或加载失败回退到用户名首字母，
/// 用户名也为空时回退到 [fallbackIcon]（默认 `?`）。
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
    this.fallbackIcon,
  });

  final String url;
  final String name;
  final double size;
  final IconData? fallbackIcon;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _failed) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = widget.url.trim();
    final name = widget.name.trim();
    final size = widget.size;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final fallback = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: name.isEmpty && widget.fallbackIcon != null
            ? Icon(
                widget.fallbackIcon,
                size: size * 0.56,
                color: colors.onSurfaceVariant,
              )
            : Text(
                name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: size * 0.42 < 11 ? 11 : size * 0.42,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
      ),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty || _failed
            ? fallback
            // 头像不走图床，没有尺寸参数，只能取原图，解码尺寸只能在客户端限制，
            // 否则 1000×1000 的原图整幅解码进 ImageCache。只给宽度：宽高都给会按精确
            // 尺寸解码，非方形头像会被压扁而不是裁切。
            : CachedNetworkImage(
                imageUrl: url,
                cacheManager: appImageCacheManager,
                width: size,
                height: size,
                memCacheWidth: pixels,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    ColoredBox(color: colors.surfaceContainerHighest),
                errorWidget: (_, _, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_failed) setState(() => _failed = true);
                  });
                  return fallback;
                },
              ),
      ),
    );
  }
}
