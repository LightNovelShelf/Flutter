import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../image_cache.dart';
import 'reveal_image.dart';
import 'user_card_sheet.dart';

/// 全站唯一的圆形头像：无地址或加载失败回退到用户名首字母，
/// 用户名也为空时回退到 [fallbackIcon]（默认 `?`）。
///
/// 传了正数 [userId] 就可点击，点开通用用户名片。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
    this.fallbackIcon,
    this.userId,
  });

  final String url;
  final String name;
  final double size;
  final IconData? fallbackIcon;
  final int? userId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = this.url.trim();
    final name = this.name.trim();
    final fallback = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: name.isEmpty && fallbackIcon != null
            ? Icon(
                fallbackIcon,
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
    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback
            : RevealImage(
                // 头像不走图床，没有尺寸参数，只能取原图，解码尺寸只能在客户端限制，
                // 否则 1000×1000 的原图整幅解码进 ImageCache。只给宽度：宽高都给会按精确
                // 尺寸解码，非方形头像会被压扁而不是裁切。
                image: ResizeImage(
                  CachedNetworkImageProvider(
                    url,
                    cacheManager: appImageCacheManager,
                  ),
                  width: (size * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                ),
                revealKey: url,
                placeholder: (_) =>
                    ColoredBox(color: colors.surfaceContainerHighest),
                errorBuilder: (_, _) => fallback,
              ),
      ),
    );
    final userId = this.userId ?? 0;
    if (userId <= 0) return avatar;
    // 卡片、列表行本身也可点，头像的手势要压过外层。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showUserCardSheet(
        context,
        userId: userId,
        userName: name,
        avatarUrl: url,
      ),
      child: avatar,
    );
  }
}
