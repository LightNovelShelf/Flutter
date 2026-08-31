import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/state_views.dart';
import '../announcement/announcement_providers.dart';

final RegExp _htmlTagPattern = RegExp('<[^>]*>');
final RegExp _danglingTagPattern = RegExp(r'<[^>]*$');
final RegExp _whitespacePattern = RegExp(r'\s+');

const Map<String, String> _htmlEntities = <String, String>{
  '&nbsp;': ' ',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&amp;': '&',
};

const int _summaryRuneLimit = 80;

final Map<String, String> _summaryCache = <String, String>{};

/// 去标签、压空白，截断到 80 字符。结果按原文缓存，列表卡片每次 build 都会调用。
String announcementSummary(String contentHtml) {
  final String? cached = _summaryCache[contentHtml];
  if (cached != null) return cached;
  if (_summaryCache.length >= 200) _summaryCache.clear();
  return _summaryCache[contentHtml] = _buildSummary(contentHtml);
}

String _stripTags(String value) => value
    .replaceAll(_htmlTagPattern, ' ')
    .replaceAll(_danglingTagPattern, ' ');

String _decodeEntities(String value) {
  var text = value;
  for (final entry in _htmlEntities.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text;
}

String _buildSummary(String contentHtml) {
  // 正文里可能出现被转义过的标签（如 `&lt;a href=...&gt;`），解码实体后会重新
  // 变成尖括号，所以要反复去标签 + 解码直到收敛，否则预览会漏出 HTML 片段。
  var text = contentHtml;
  for (var pass = 0; pass < 4; pass += 1) {
    final next = _decodeEntities(_stripTags(text));
    if (next == text) break;
    text = next;
  }
  text = _stripTags(text).replaceAll(_whitespacePattern, ' ').trim();
  // 数到第 81 个 rune 即可判断是否需要截断。
  final RuneIterator runes = text.runes.iterator;
  var count = 0;
  while (count <= _summaryRuneLimit && runes.moveNext()) {
    count += 1;
  }
  if (count <= _summaryRuneLimit) return text;
  return '${text.substring(0, runes.rawIndex)}…';
}

class AnnouncementCenterScreen extends ConsumerWidget {
  const AnnouncementCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(announcementCenterProvider);
    final controller = ref.read(announcementCenterProvider.notifier);
    final canLoadMore = state.hasMore && state.loadMoreError == null;

    final Widget body;
    if (state.items.isEmpty) {
      if (state.loading) {
        body = ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 48),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => const _AnnouncementCardSkeleton(),
        );
      } else {
        final message = state.error;
        body = ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            if (message != null)
              ErrorStateView(
                message: message,
                title: '无法加载公告',
                onRetry: controller.retry,
              )
            else
              const EmptyStateView(
                icon: Icons.campaign_outlined,
                title: '暂无公告',
                description: '目前没有可查看的公告。',
              ),
          ],
        );
      }
    } else {
      body = PrefetchOnScroll(
        onLoadMore: () {
          if (!canLoadMore || state.loadingMore) return;
          controller.loadMore();
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 48),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: state.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == state.items.length) {
              return ListFooterStatus(
                loading: state.loadingMore,
                hasMore: state.hasMore,
                error: state.loadMoreError,
                onRetry: controller.loadMore,
              );
            }
            final item = state.items[index];
            return _AnnouncementCard(
              item: item,
              onTap: () => context.push('/announcement/${item.id}'),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('公告')),
      body: RefreshIndicator(onRefresh: controller.refresh, child: body),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item, required this.onTap});

  final AnnouncementItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = announcementSummary(item.contentHtml);
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 122),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.public,
                        size: 21,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              height: 21 / 16,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                          if (summary.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 5),
                            Text(
                              summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 20 / 14,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 54),
                  child: Text(
                    '${formatShortDate(item.createdAt)} · 站点公告',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementCardSkeleton extends StatelessWidget {
  const _AnnouncementCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget block({
      required double height,
      double? width,
      double radius = 6,
      double? widthFactor,
    }) {
      final box = Container(
        width: width,
        height: height,
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

    return Container(
      height: 122,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              block(height: 42, width: 42, radius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    block(height: 16, widthFactor: 0.58),
                    const SizedBox(height: 6),
                    block(height: 12, widthFactor: 1),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              block(height: 20, width: 20),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 54),
            child: block(height: 12, widthFactor: 0.44),
          ),
        ],
      ),
    );
  }
}
