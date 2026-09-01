import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/format.dart';
import '../../shared/paging/paged_list.dart';
import '../../shared/paging/paged_list_controller.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/app_sheet.dart';
import '../../shared/widgets/state_views.dart';

enum PointLogKind { experience, coin }

Future<void> showPointLogSheet(
  BuildContext context, {
  required PointLogKind kind,
}) async {
  await showDraggableSheet<void>(
    context,
    initialSize: 0.68,
    showDragHandle: true,
    builder: (_, controller) =>
        _PointLogSheet(kind: kind, scrollController: controller),
  );
}

class _PointLogController
    extends PagedListController<PointLogEntry, PointLogKind> {
  _PointLogController(super.arg);

  @override
  void subscribe() {
    ref.watch(apiClientProvider);
  }

  @override
  Object idOf(PointLogEntry item) => (
    item.source,
    item.amount,
    item.balance,
    item.referenceId,
    item.occurredAt,
  );

  @override
  Future<FetchedPage<PointLogEntry>> fetchPage(int page) async {
    final api = ref.read(apiClientProvider);
    final response = arg == PointLogKind.coin
        ? await api.getCoinLog(page: page)
        : await api.getPointLog(page: page);
    return FetchedPage<PointLogEntry>(
      items: response.items,
      page: response.page,
      totalPages: response.totalPages,
    );
  }
}

final NotifierProviderFamily<
  _PointLogController,
  PagedList<PointLogEntry>,
  PointLogKind
>
_pointLogProvider =
    NotifierProvider.family<
      _PointLogController,
      PagedList<PointLogEntry>,
      PointLogKind
    >(_PointLogController.new, isAutoDispose: true);

class _PointLogSheet extends ConsumerWidget {
  const _PointLogSheet({required this.kind, required this.scrollController});

  final PointLogKind kind;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _pointLogProvider(kind);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final title = kind == PointLogKind.coin ? '金币记录' : '经验记录';
    final icon = kind == PointLogKind.coin
        ? Icons.paid_outlined
        : Icons.show_chart;

    if (state.hasMore && !state.loadingMore && state.loadMoreError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients &&
            scrollController.position.extentAfter < 200) {
          controller.loadMore();
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(icon: icon, title: title),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, state, controller)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    PagedList<PointLogEntry> state,
    _PointLogController controller,
  ) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return ErrorStateView(message: state.error!, onRetry: controller.retry);
    }
    if (state.items.isEmpty) {
      return const EmptyStateView(icon: Icons.history, title: '暂无记录');
    }

    return PrefetchOnScroll(
      threshold: 200,
      onLoadMore: controller.loadMore,
      child: ListView.separated(
        controller: scrollController,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, index) => index < state.items.length - 1
            ? const Divider(height: 1, indent: 16, endIndent: 16)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return ListFooterStatus(
              loading: state.loadingMore,
              hasMore: state.hasMore,
              error: state.loadMoreError,
              onRetry: controller.loadMore,
              endLabel: '没有更多记录了',
            );
          }
          return _PointLogTile(entry: state.items[index]);
        },
      ),
    );
  }
}

class _PointLogTile extends StatelessWidget {
  const _PointLogTile({required this.entry});

  final PointLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amount =
        '${entry.amount >= 0 ? '+' : ''}${formatCount(entry.amount)}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(entry.sourceLabel),
      subtitle: Text(formatRelativeTime(entry.occurredAt)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            amount,
            style: TextStyle(
              color: entry.amount >= 0 ? colors.primary : colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '余 ${formatCount(entry.balance)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
