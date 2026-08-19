import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/api/community_models.dart';
import '../../../shared/image_cache.dart';
import '../community_providers.dart';

/// 精选星标用固定的琥珀色，不随主题走。
const Color communityFeaturedColor = Color(0xFFF59E0B);
const Color _lockedBackground = Color(0xFFFEF3C7);
const Color _lockedForeground = Color(0xFFB45309);

const List<Color> _rankColors = <Color>[
  Color(0xFFF59E0B),
  Color(0xFFFB7185),
  Color(0xFF60A5FA),
];

const TextStyle _tabular = TextStyle(
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

/// 社区通用卡片：不投阴影，只有一条发丝边框。
class CommunityCard extends StatelessWidget {
  const CommunityCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.background,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? colors.outlineVariant, width: 0.5),
    );
    return Material(
      color: background ?? colors.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 头像：地址为空或加载失败时回落到首字母。
class CommunityAvatar extends StatefulWidget {
  const CommunityAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
  });

  final String url;
  final String name;
  final double size;

  @override
  State<CommunityAvatar> createState() => _CommunityAvatarState();
}

class _CommunityAvatarState extends State<CommunityAvatar> {
  bool _failed = false;

  @override
  void didUpdateWidget(covariant CommunityAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 地址换了就再给网络图一次机会。
    if (oldWidget.url != widget.url && _failed) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = widget.url.trim();
    final initial = _initial(widget.name);
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: url.isEmpty || _failed
            ? Container(
                color: colors.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: widget.size >= 38 ? 14 : 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              )
            // 头像不走图床，没有尺寸参数可用，只能整张取。
            : CachedNetworkImage(
                imageUrl: url,
                cacheManager: appImageCacheManager,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    ColoredBox(color: colors.surfaceContainerHighest),
                errorWidget: (_, _, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_failed) setState(() => _failed = true);
                  });
                  return ColoredBox(color: colors.surfaceContainerHighest);
                },
              ),
      ),
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class CommunityFilterChip extends StatelessWidget {
  const CommunityFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? colors.onPrimaryContainer : colors.primary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityFilterCaption extends StatelessWidget {
  const CommunityFilterCaption({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 静态标签胶囊：版面用强调色，子分类/状态用中性色。
class CommunityTagPill extends StatelessWidget {
  const CommunityTagPill({
    super.key,
    required this.label,
    this.tone = CommunityTagTone.accent,
  });

  final String label;
  final CommunityTagTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground, FontWeight weight) =
        switch (tone) {
      CommunityTagTone.accent => (
          colors.primaryContainer,
          colors.onPrimaryContainer,
          FontWeight.w700,
        ),
      CommunityTagTone.neutral => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          FontWeight.w600,
        ),
      CommunityTagTone.locked => (
          _lockedBackground,
          _lockedForeground,
          FontWeight.w700,
        ),
    };
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: weight, color: foreground),
      ),
    );
  }
}

enum CommunityTagTone { accent, neutral, locked }

/// 帖子卡片：社区首页、我的社区共用。
class CommunityFeedCard extends StatelessWidget {
  const CommunityFeedCard({super.key, required this.item, required this.onTap});

  final CommunityFeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final subCategory = item.subCategoryLabel?.trim() ?? '';
    return CommunityCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CommunityAvatar(
            url: item.authorAvatar,
            name: _authorName(item),
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            if (item.pinned)
                              _iconSpan(Icons.push_pin, colors.primary),
                            if (item.featured)
                              _iconSpan(Icons.star, communityFeaturedColor),
                            if (item.locked)
                              _iconSpan(Icons.lock, colors.onSurfaceVariant),
                            TextSpan(text: item.title),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 21 / 16,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (item.replies > 0) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.mode_comment_outlined,
                              size: 13,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatCommunityCount(item.replies),
                              style: _tabular.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.excerpt.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 7),
                  Text(
                    item.excerpt.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (item.boardName.trim().isNotEmpty)
                      CommunityTagPill(label: item.boardName),
                    if (subCategory.isNotEmpty)
                      CommunityTagPill(
                        label: subCategory,
                        tone: CommunityTagTone.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: _authorName(item),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            if (item.authorIsDeleted &&
                                item.authorName.trim().isNotEmpty)
                              TextSpan(
                                text: '（已注销）',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colors.error,
                                ),
                              ),
                            TextSpan(
                              text: ' · ${formatCommunityTime(item.publishedAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _MetricLabel(
                      icon: Icons.visibility_outlined,
                      value: item.views,
                    ),
                    const SizedBox(width: 10),
                    _MetricLabel(
                      icon: Icons.favorite_border,
                      value: item.likes,
                    ),
                    if (item.favorites > 0) ...<Widget>[
                      const SizedBox(width: 10),
                      _MetricLabel(
                        icon: Icons.bookmark_border,
                        value: item.favorites,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _authorName(CommunityFeedItem item) {
    final name = item.authorName.trim();
    if (name.isNotEmpty) return name;
    return item.authorIsDeleted ? '已注销用户' : '未知用户';
  }

  static InlineSpan _iconSpan(IconData icon, Color color) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(icon, size: 15, color: color),
        ),
      );
}

class _MetricLabel extends StatelessWidget {
  const _MetricLabel({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          formatCommunityCount(value),
          style: _tabular.copyWith(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class CommunitySkeletonBox extends StatelessWidget {
  const CommunitySkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.widthFactor,
    this.radius = 8,
  });

  final double height;
  final double? width;
  final double? widthFactor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: box,
    );
  }
}

class CommunityFeedCardSkeleton extends StatelessWidget {
  const CommunityFeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => CommunityCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CommunitySkeletonBox(height: 42, width: 42, radius: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  CommunitySkeletonBox(height: 42, widthFactor: 0.88),
                  SizedBox(height: 7),
                  CommunitySkeletonBox(height: 20, widthFactor: 1),
                  SizedBox(height: 7),
                  CommunitySkeletonBox(height: 20, widthFactor: 0.88),
                  SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      CommunitySkeletonBox(height: 20, width: 62, radius: 999),
                      SizedBox(width: 6),
                      CommunitySkeletonBox(height: 20, width: 78, radius: 999),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CommunitySkeletonBox(
                          height: 16,
                          widthFactor: 0.44,
                        ),
                      ),
                      CommunitySkeletonBox(height: 12, width: 24),
                      SizedBox(width: 10),
                      CommunitySkeletonBox(height: 12, width: 24),
                      SizedBox(width: 10),
                      CommunitySkeletonBox(height: 12, width: 24),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 卡片形态的空/错误状态，夹在列表中间用。
class CommunityStateCard extends StatelessWidget {
  const CommunityStateCard({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.forum_outlined,
    this.isError = false,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isError;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CommunityCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              isError ? Icons.error_outline : icon,
              size: 22,
              color: isError ? colors.error : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// 帖子详情里的一条回复（父级/子级共用）。
class CommunityReplyRow extends StatelessWidget {
  const CommunityReplyRow({
    super.key,
    required this.reply,
    required this.isChild,
    required this.highlighted,
    required this.canReply,
    required this.busy,
    required this.onLike,
    required this.onReply,
  });

  final CommunityThreadReply reply;
  final bool isChild;
  final bool highlighted;
  final bool canReply;
  final bool busy;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = _displayName(reply.authorName, reply.authorIsDeleted);
    final badge = reply.authorBadge?.trim() ?? '';
    final replyToName = reply.replyTo == null
        ? ''
        : _displayName(reply.replyTo!.authorName, reply.replyTo!.authorIsDeleted);

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (isChild)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              CommunityAvatar(
                url: reply.authorAvatar,
                name: name,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (replyToName.isNotEmpty)
                        TextSpan(
                          text: ' 回复了 $replyToName',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (badge.isNotEmpty) _BadgePill(label: badge),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CommunityAvatar(
                url: reply.authorAvatar,
                name: name,
                size: 40,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 19 / 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (badge.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 8),
                          _BadgePill(label: badge),
                        ],
                      ],
                    ),
                    if (replyToName.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '回复 $replyToName',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: isChild ? 0 : 56),
          child: SelectionArea(
            child: Text(
              reply.content.trim(),
              style: TextStyle(
                fontSize: 14,
                height: 19 / 14,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: isChild ? 0 : 56),
          child: _ReplyActions(
            reply: reply,
            compact: isChild,
            canReply: canReply,
            busy: busy,
            onLike: onLike,
            onReply: onReply,
          ),
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: highlighted ? colors.primaryContainer : Colors.transparent,
        border: highlighted
            ? Border(left: BorderSide(color: colors.primary, width: 3))
            : null,
        borderRadius: BorderRadius.circular(highlighted ? 12 : 0),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: highlighted ? 6 : 0,
        vertical: isChild ? 2 : 8,
      ),
      child: content,
    );
  }

  static String _displayName(String name, bool deleted) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return deleted ? '已注销用户' : '未知用户';
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReplyActions extends StatelessWidget {
  const _ReplyActions({
    required this.reply,
    required this.compact,
    required this.canReply,
    required this.busy,
    required this.onLike,
    required this.onReply,
  });

  final CommunityThreadReply reply;
  final bool compact;
  final bool canReply;
  final bool busy;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = compact ? 16.0 : 18.0;
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatCommunityTime(reply.publishedAt),
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          InkWell(
            onTap: busy ? null : onLike,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    reply.liked ? Icons.favorite : Icons.favorite_border,
                    size: iconSize,
                    color: reply.liked ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatCommunityCount(reply.likes),
                    style: _tabular.copyWith(
                      fontSize: 12,
                      color: reply.liked ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: iconSize,
              onPressed: canReply && !busy ? onReply : null,
              icon: const Icon(Icons.reply),
              tooltip: '回复',
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityHotThreadsPanel extends StatelessWidget {
  const CommunityHotThreadsPanel({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<CommunityHotRankItem> items;
  final void Function(int threadId) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CommunityCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.local_fire_department, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                '热门讨论',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (int index = 0; index < items.length; index += 1) ...<Widget>[
            if (index > 0) Divider(height: 1, color: colors.outlineVariant),
            InkWell(
              onTap: () => onOpen(items[index].id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    _RankBadge(rank: index + 1),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            items[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(items[index]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 16 / 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(CommunityHotRankItem item) {
    final parts = <String>[
      if (item.boardName.trim().isNotEmpty) item.boardName.trim(),
      '热度 ${formatCommunityCount(item.heat)}',
      if (formatCommunityTime(item.publishedAt).isNotEmpty)
        formatCommunityTime(item.publishedAt),
    ];
    return parts.join(' · ');
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = rank <= _rankColors.length ? _rankColors[rank - 1] : null;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent == null
            ? colors.surfaceContainerHighest
            : accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: accent ?? colors.primary,
        ),
      ),
    );
  }
}

class CommunityActiveUsersPanel extends StatelessWidget {
  const CommunityActiveUsersPanel({super.key, required this.users});

  final List<CommunityActiveUserItem> users;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CommunityCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.emoji_events_outlined, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                '活跃成员',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (int index = 0; index < users.length; index += 1) ...<Widget>[
            if (index > 0) Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  CommunityAvatar(
                    url: users[index].avatar,
                    name: users[index].name,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          users[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(users[index]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      formatCommunityCount(users[index].score),
                      style: _tabular.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(CommunityActiveUserItem user) {
    if (user.summary.trim().isNotEmpty) return user.summary.trim();
    if (user.badge.trim().isNotEmpty) return user.badge.trim();
    return '社区成员';
  }
}
