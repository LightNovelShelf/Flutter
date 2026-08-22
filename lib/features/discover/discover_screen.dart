import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/widgets/state_views.dart';
import 'home_providers.dart';
import 'widgets/book_grid.dart';

/// 发现页：排行榜 / 全部小说 / 全部漫画 / 服务状态 / 公告。
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  /// 吞掉单个分区的失败，避免整体刷新提前结束。
  static Future<void> _reload(Future<Object?> future) async {
    try {
      await future;
    } catch (_) {
      // 错误由对应分区的状态展示。
    }
  }

  Future<void> _refreshAll(WidgetRef ref) => Future.wait<void>(<Future<void>>[
    for (final spec in _sections) _reload(ref.refresh(spec.provider.future)),
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
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
            sliver: SliverList(delegate: _sectionDelegate),
          ),
        ],
      ),
    ),
  );
}

/// 分区惰性构建：屏外分区不提前建封面行，任一分区的数据到达也不会重建整屏。
/// 建过的分区不再卸载，见 [_DiscoverSectionState]。
final SliverChildDelegate _sectionDelegate = _SectionListDelegate();

class _SectionListDelegate extends SliverChildBuilderDelegate {
  _SectionListDelegate()
    : super(
        (context, index) => _DiscoverSection(index: index),
        childCount: _sections.length,
        addAutomaticKeepAlives: true,
      );

  /// 分区列表是编译期固定的，子节点只认下标。
  @override
  bool shouldRebuild(covariant _SectionListDelegate oldDelegate) => false;
}

/// 单个分区：自己订阅数据源与排行周期，重建范围止于这张卡片。
///
/// 建过之后常驻：分区滚出视口被卸载会带走 provider 唯一的监听者，`isAutoDispose`
/// 的数据源随即丢弃数据，滚回来要重新请求，先出骨架再补图。发现页只有五个分区，
/// 常驻的代价远小于每次回滚重来一遍。
class _DiscoverSection extends ConsumerStatefulWidget {
  const _DiscoverSection({required this.index});

  final int index;

  @override
  ConsumerState<_DiscoverSection> createState() => _DiscoverSectionState();
}

class _DiscoverSectionState extends ConsumerState<_DiscoverSection>
    with AutomaticKeepAliveClientMixin<_DiscoverSection> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final spec = _sections[widget.index];
    final String title;
    if (spec.showRankPeriod) {
      final period = ref.watch(
        appSettingsProvider.select((settings) => settings.homeRankType),
      );
      title = '${spec.title} · ${rankPeriodLabels[period]}';
    } else {
      title = spec.title;
    }
    return Padding(
      padding: EdgeInsets.only(top: widget.index == 0 ? 0 : 18),
      child: _AsyncSection(
        spec: spec,
        title: title,
        value: ref.watch(spec.provider),
        onRetry: () => ref.invalidate(spec.provider),
      ),
    );
  }
}

/// 分区配置表：文案、路由、数据源。
///
/// 字段按 `Object` 存，向下转型集中在 [of]。函数类型的参数逆变，泛型字段无法从
/// `_SectionSpec<Object>` 视图读取。
class _SectionSpec {
  const _SectionSpec._({
    required this.title,
    required this.provider,
    required this.body,
    required this.skeleton,
    required this.isEmpty,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.errorTitle,
    required this.errorDescription,
    required this.route,
    required this.showRankPeriod,
  });

  static _SectionSpec of<T extends Object>({
    required String title,
    required FutureProvider<T> provider,
    required Widget Function(BuildContext context, T value) body,
    required Widget skeleton,
    required bool Function(T value) isEmpty,
    required String emptyTitle,
    required String emptyDescription,
    required String errorTitle,
    required String errorDescription,
    String? route,
    bool showRankPeriod = false,
  }) => _SectionSpec._(
    title: title,
    provider: provider,
    body: (context, value) => body(context, value as T),
    skeleton: skeleton,
    isEmpty: (value) => isEmpty(value as T),
    emptyTitle: emptyTitle,
    emptyDescription: emptyDescription,
    errorTitle: errorTitle,
    errorDescription: errorDescription,
    route: route,
    showRankPeriod: showRankPeriod,
  );

  final String title;

  /// 非空时标题右侧显示「查看全部」，点击跳转该路由。
  final String? route;
  final FutureProvider<Object> provider;
  final Widget Function(BuildContext context, Object value) body;
  final Widget skeleton;
  final bool Function(Object value) isEmpty;
  final String emptyTitle;
  final String emptyDescription;
  final String errorTitle;
  final String errorDescription;

  /// 为 true 时标题附加当前排行周期。
  final bool showRankPeriod;
}

final List<_SectionSpec> _sections = <_SectionSpec>[
  _SectionSpec.of<List<BookListItem>>(
    title: '排行榜',
    showRankPeriod: true,
    route: '/ranking',
    provider: homeRankingProvider,
    body: (context, books) => BookGridPreview(
      books: books,
      onOpen: (book) => openBookDetail(context, book),
      showRank: true,
    ),
    skeleton: const BookGridPreviewSkeleton(),
    isEmpty: (books) => books.isEmpty,
    emptyTitle: '暂无排行',
    emptyDescription: '当前周期暂无排行数据。',
    errorTitle: '无法加载排行榜',
    errorDescription: '排行榜暂不可用。',
  ),
  _SectionSpec.of<List<BookListItem>>(
    title: '全部小说',
    route: '/books',
    provider: homeLatestBooksProvider,
    body: _bookPreview,
    skeleton: const BookGridPreviewSkeleton(),
    isEmpty: (books) => books.isEmpty,
    emptyTitle: '暂无小说',
    emptyDescription: '书库目前没有可显示的小说。',
    errorTitle: '无法加载小说',
    errorDescription: '书库暂不可用。',
  ),
  _SectionSpec.of<List<BookListItem>>(
    title: '全部漫画',
    route: '/comics',
    provider: homeComicsProvider,
    body: _bookPreview,
    skeleton: const BookGridPreviewSkeleton(),
    isEmpty: (books) => books.isEmpty,
    emptyTitle: '暂无漫画',
    emptyDescription: '漫画库目前没有可显示的漫画。',
    errorTitle: '无法加载漫画',
    errorDescription: '漫画库暂不可用。',
  ),
  _SectionSpec.of<OnlineInfo>(
    title: '服务状态',
    provider: onlineInfoProvider,
    body: (context, info) => _StatusMetrics(info: info),
    skeleton: const _StatusMetricsSkeleton(),
    // 服务状态是单条记录，不存在空结果。
    isEmpty: (_) => false,
    emptyTitle: '暂无数据',
    emptyDescription: '服务状态暂不可用。',
    errorTitle: '无法加载服务状态',
    errorDescription: '服务状态暂不可用。',
  ),
  _SectionSpec.of<List<AnnouncementItem>>(
    title: '公告',
    route: '/announcements',
    provider: homeAnnouncementsProvider,
    body: (context, items) => _AnnouncementStrip(items: items),
    skeleton: const _AnnouncementStripSkeleton(),
    isEmpty: (items) => items.isEmpty,
    emptyTitle: '暂无公告',
    emptyDescription: '目前没有新的公告。',
    errorTitle: '无法加载公告',
    errorDescription: '公告服务暂不可用。',
  ),
];

Widget _bookPreview(BuildContext context, List<BookListItem> books) =>
    BookGridPreview(
      books: books,
      onOpen: (book) => openBookDetail(context, book),
    );

/// 分区外壳：按 AsyncValue 分别渲染骨架 / 错误 / 空 / 内容（含陈旧数据提示）。
class _AsyncSection extends StatelessWidget {
  const _AsyncSection({
    required this.spec,
    required this.title,
    required this.value,
    required this.onRetry,
  });

  final _SectionSpec spec;

  /// 分区标题，排行榜随周期变化，不使用 spec 中的静态文案。
  final String title;
  final AsyncValue<Object> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final data = value.value;
    final Widget content;
    if (data != null && !spec.isEmpty(data)) {
      final error = value.error;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          spec.body(context, data),
          if (error != null) ...<Widget>[
            const SizedBox(height: 10),
            _StaleWarning(message: describeApiError(error), onRetry: onRetry),
          ],
        ],
      );
    } else if (value.isLoading) {
      content = spec.skeleton;
    } else if (value.hasError) {
      content = _SectionError(
        title: spec.errorTitle,
        description: spec.errorDescription,
        onRetry: onRetry,
      );
    } else {
      content = _SectionMessage(
        title: spec.emptyTitle,
        description: spec.emptyDescription,
      );
    }

    final route = spec.route;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: title,
            actionLabel: route == null ? null : '查看全部',
            onAction: route == null ? null : () => context.push(route),
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
