import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/models.dart';
import '../../../shared/format.dart';
import '../community_thread_providers.dart';
import 'community_feed_card.dart';
import 'community_primitives.dart';

/// 帖子尾部：翻页状态与相关讨论。`SliverToBoxAdapter` 的子节点不管可不可见都会建。
class CommunityThreadFooter extends StatelessWidget {
  const CommunityThreadFooter({
    super.key,
    required this.detail,
    required this.controller,
    required this.loadingMore,
    required this.loadMoreError,
  });

  final CommunityThreadDetail? detail;
  final CommunityThreadController controller;
  final bool loadingMore;
  final String? loadMoreError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final detail = this.detail;
    if (detail == null) return const SizedBox.shrink();
    final children = <Widget>[
      CommunityLoadMoreFooter(
        loading: loadingMore,
        error: loadMoreError,
        onRetry: controller.loadMore,
      ),
    ];
    if (!detail.repliesPage.hasMore && detail.relatedThreads.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            '相关讨论',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ),
      );
      for (final CommunityFeedItem related in detail.relatedThreads) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CommunityCard(
              radius: 18,
              padding: const EdgeInsets.all(14),
              onTap: () =>
                  context.pushReplacement('/community/thread/${related.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    related.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      if (related.boardName.trim().isNotEmpty)
                        CommunityTagPill(label: related.boardName),
                      if (related.replies > 0) ...<Widget>[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(related.replies),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
