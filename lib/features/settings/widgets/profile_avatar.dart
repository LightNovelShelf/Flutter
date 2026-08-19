import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 圆形头像：无地址或加载失败时回退到用户名首字母，用户名为空时回退到人形图标。
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.url,
    required this.userName,
    this.size = 48,
  });

  final String url;
  final String userName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final trimmedUrl = url.trim();
    final trimmedName = userName.trim();
    final fallback = Center(
      child: trimmedName.isEmpty
          ? Icon(
              Icons.person,
              size: size * 0.56,
              color: colors.onSurfaceVariant,
            )
          : Text(
              trimmedName.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: trimmedUrl.isEmpty
              ? fallback
              : CachedNetworkImage(
                  imageUrl: trimmedUrl,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
