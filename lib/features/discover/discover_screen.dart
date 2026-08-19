import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets/state_views.dart';
import 'discover_providers.dart';
import 'widgets/book_grid.dart';

/// 发现页：排行榜 / 全部小说 / 全部漫画 / 服务状态 / 公告。
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  /// 单个分区失败不该影响整体刷新手势，各分区自己展示错误。
  static Future<void> _reload(Future<Object?> future) async {
    try {
      await future;
    } catch (_) {
      // 忽略：错误已经反映在对应分区的状态里。
    }
  }

  Future<void> _refreshAll(WidgetRef ref) => Future.wait<void>(<Future<void>>[
    _reload(ref.refresh(homeRankingProvider.future)),
    _reload(ref.refresh(homeLatestBooksProvider.future)),
    _reload(ref.refresh(homeComicsProvider.future)),
    _reload(ref.refresh(onlineInfoProvider.future)),
    _reload(ref.refresh(homeAnnouncementsProvider.future)),
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(
      appSettingsProvider.select((settings) => settings.homeRankType),
    );
    final ranking = ref.watch(homeRankingProvider);
    final books = ref.watch(homeLatestBooksProvider);
    final comics = ref.watch(homeComicsProvider);
    final online = ref.watch(onlineInfoProvider);
    final announcements = ref.watch(homeAnnouncementsProvider);

    void open(BookListItem book) => openBookDetail(context, book);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refreshAll(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              title: const Text('发现'),
              actions: <Widget>[
                IconButton(
                  tooltip: '个人资料与设置',
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  _AsyncSection<List<BookListItem>>(
                    title: '排行榜 · ${rankPeriodLabels[period]}',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/ranking'),
                    value: ranking,
                    isEmpty: (items) => items.isEmpty,
                    body: (items) => BookGridPreview(
                      books: items,
                      onOpen: open,
                      showRank: true,
                    ),
                    skeleton: const BookGridPreviewSkeleton(),
                    emptyTitle: '暂无排行',
                    emptyDescription: '当前周期暂无排行数据。',
                    errorTitle: '无法加载排行榜',
                    errorDescription: '排行榜暂不可用。',
                    onRetry: () => ref.invalidate(homeRankingProvider),
                  ),
                  const SizedBox(height: 18),
                  _AsyncSection<List<BookListItem>>(
                    title: '全部小说',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/books'),
                    value: books,
                    isEmpty: (items) => items.isEmpty,
                    body: (items) =>
                        BookGridPreview(books: items, onOpen: open),
                    skeleton: const BookGridPreviewSkeleton(),
                    emptyTitle: '暂无小说',
                    emptyDescription: '书库目前没有可显示的小说。',
                    errorTitle: '无法加载小说',
                    errorDescription: '书库暂不可用。',
                    onRetry: () => ref.invalidate(homeLatestBooksProvider),
                  ),
                  const SizedBox(height: 18),
                  _AsyncSection<List<BookListItem>>(
                    title: '全部漫画',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/comics'),
                    value: comics,
                    isEmpty: (items) => items.isEmpty,
                    body: (items) =>
                        BookGridPreview(books: items, onOpen: open),
                    skeleton: const BookGridPreviewSkeleton(),
                    emptyTitle: '暂无漫画',
                    emptyDescription: '漫画库目前没有可显示的漫画。',
                    errorTitle: '无法加载漫画',
                    errorDescription: '漫画库暂不可用。',
                    onRetry: () => ref.invalidate(homeComicsProvider),
                  ),
                  const SizedBox(height: 18),
                  _AsyncSection<OnlineInfo>(
                    title: '服务状态',
                    value: online,
                    isEmpty: (_) => false,
                    body: (info) => _StatusMetrics(info: info),
                    skeleton: const _StatusMetricsSkeleton(),
                    emptyTitle: '暂无数据',
                    emptyDescription: '服务状态暂不可用。',
                    errorTitle: '无法加载服务状态',
                    errorDescription: '服务状态暂不可用。',
                    onRetry: () => ref.invalidate(onlineInfoProvider),
                  ),
                  const SizedBox(height: 18),
                  _AsyncSection<List<AnnouncementItem>>(
                    title: '公告',
                    actionLabel: '查看全部',
                    onAction: () => context.push('/announcements'),
                    value: announcements,
                    isEmpty: (items) => items.isEmpty,
                    body: (items) => _AnnouncementStrip(items: items),
                    skeleton: const _AnnouncementStripSkeleton(),
                    emptyTitle: '暂无公告',
                    emptyDescription: '目前没有新的公告。',
                    errorTitle: '无法加载公告',
                    errorDescription: '公告服务暂不可用。',
                    onRetry: () => ref.invalidate(homeAnnouncementsProvider),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分区外壳：按 AsyncValue 分别渲染骨架 / 错误 / 空 / 内容（含陈旧数据提示）。
class _AsyncSection<T> extends StatelessWidget {
  const _AsyncSection({
    super.key,
    required this.title,
    required this.value,
    required this.isEmpty,
    required this.body,
    required this.skeleton,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.errorTitle,
    required this.errorDescription,
    required this.onRetry,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final AsyncValue<T> value;
  final bool Function(T value) isEmpty;
  final Widget Function(T value) body;
  final Widget skeleton;
  final String emptyTitle;
  final String emptyDescription;
  final String errorTitle;
  final String errorDescription;
  final VoidCallback onRetry;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final data = value.value;
    final Widget content;
    if (data != null && !isEmpty(data)) {
      final error = value.error;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          body(data),
          if (error != null) ...<Widget>[
            const SizedBox(height: 10),
            _StaleWarning(message: describeApiError(error), onRetry: onRetry),
          ],
        ],
      );
    } else if (value.isLoading) {
      content = skeleton;
    } else if (value.hasError) {
      content = _SectionError(
        title: errorTitle,
        description: errorDescription,
        onRetry: onRetry,
      );
    } else {
      content = _SectionMessage(
        title: emptyTitle,
        description: emptyDescription,
      );
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: title,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.title,
    required this.description,
    required this.onRetry,
  });

  final String title;
  final String description;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _SectionMessage(title: title, description: description),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ),
    ],
  );
}

/// 已有数据但刷新失败：保留内容，底部追加可点击的提示条。
class _StaleWarning extends StatelessWidget {
  const _StaleWarning({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onRetry,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$message 点击重试。',
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _StatusMetrics extends StatelessWidget {
  const _StatusMetrics({required this.info});

  final OnlineInfo info;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: _StatusMetric(label: '在线', value: info.onlineUserCount),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: _StatusMetric(label: '今日', value: info.dayCount),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: _StatusMetric(label: '新用户', value: info.dayRegister),
      ),
    ],
  );
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Text(
          formatCount(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatusMetricsSkeleton extends StatelessWidget {
  const _StatusMetricsSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height, double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    Widget metric() => Expanded(
      child: Column(
        children: <Widget>[
          block(24, 0.44),
          const SizedBox(height: 5),
          block(12, 0.58),
        ],
      ),
    );

    return Row(
      children: <Widget>[
        metric(),
        const SizedBox(width: 14),
        metric(),
        const SizedBox(width: 14),
        metric(),
      ],
    );
  }
}

class _AnnouncementStrip extends StatelessWidget {
  const _AnnouncementStrip({required this.items});

  final List<AnnouncementItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        for (final item in items)
          InkWell(
            onTap: () => context.push('/announcement/${item.id}'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.campaign_outlined,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: colors.onSurface),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatShortDate(item.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AnnouncementStripSkeleton extends StatelessWidget {
  const _AnnouncementStripSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      children: <Widget>[
        for (var index = 0; index < 3; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: index.isEven ? 0.82 : 0.64,
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
