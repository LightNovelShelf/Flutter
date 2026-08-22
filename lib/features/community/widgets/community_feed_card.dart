import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'community_primitives.dart';

/// 帖子卡片，社区首页与我的社区共用。
class CommunityFeedCard extends StatelessWidget {
  const CommunityFeedCard({super.key, required this.item, required this.onTap});

  final CommunityFeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final subCategory = item.subCategoryLabel?.trim() ?? '';
    final authorName = displayUserName(
      item.authorName,
      deleted: item.authorIsDeleted,
    );
    return CommunityCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UserAvatar(url: item.authorAvatar, name: authorName, size: 42),
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
                              formatCompactCount(item.replies),
                              style: communityTabular.copyWith(
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
                              text: authorName,
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
                              text:
                                  ' · ${formatRelativeTimeFine(item.publishedAt)}',
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
          formatCompactCount(value),
          style: communityTabular.copyWith(
            fontSize: 12,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
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
        const SkeletonBox(height: 42, width: 42, radius: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const <Widget>[
              SkeletonBox(height: 42, widthFactor: 0.88),
              SizedBox(height: 7),
              SkeletonBox(height: 20, widthFactor: 1),
              SizedBox(height: 7),
              SkeletonBox(height: 20, widthFactor: 0.88),
              SizedBox(height: 10),
              Row(
                children: <Widget>[
                  SkeletonBox(height: 20, width: 62, radius: 999),
                  SizedBox(width: 6),
                  SkeletonBox(height: 20, width: 78, radius: 999),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(child: SkeletonBox(height: 16, widthFactor: 0.44)),
                  SkeletonBox(height: 12, width: 24),
                  SizedBox(width: 10),
                  SkeletonBox(height: 12, width: 24),
                  SizedBox(width: 10),
                  SkeletonBox(height: 12, width: 24),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 帖子流底部的翻页状态，加载中显示骨架，失败显示可重试的错误卡，到底显示结束提示。
class CommunityLoadMoreFooter extends StatelessWidget {
  const CommunityLoadMoreFooter({
    super.key,
    required this.loading,
    required this.onRetry,
    this.error,
    this.atEnd = false,
    this.endLabel = '没有更多内容了',
  });

  final bool loading;
  final VoidCallback onRetry;
  final String? error;
  final bool atEnd;
  final String endLabel;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Column(
        children: <Widget>[
          CommunityFeedCardSkeleton(),
          SizedBox(height: 8),
          CommunityFeedCardSkeleton(),
        ],
      );
    }
    final message = error;
    if (message != null) {
      return CommunityStateCard(
        title: '无法加载更多',
        description: message,
        isError: true,
        onRetry: onRetry,
      );
    }
    if (!atEnd) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.check_circle_outline,
          size: 17,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Text(
          endLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
