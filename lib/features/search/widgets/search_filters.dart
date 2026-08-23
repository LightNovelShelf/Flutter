import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../search_providers.dart';

const Map<BookSearchMode, String> _modeLabels = <BookSearchMode, String>{
  BookSearchMode.fuzzy: '模糊',
  BookSearchMode.exact: '精确',
  BookSearchMode.title: '标题',
  BookSearchMode.author: '作者',
  BookSearchMode.name: '系列',
  BookSearchMode.tags: '标签',
};

/// 搜索条件区。整块不订阅搜索状态，翻页时输入框与筛选行都不重建。
class SearchHeader extends ConsumerWidget {
  const SearchHeader({
    super.key,
    required this.input,
    required this.focus,
    required this.hasInput,
    required this.onUseKeyword,
  });

  final TextEditingController input;
  final FocusNode focus;
  final bool hasInput;
  final void Function(String keyword) onUseKeyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final controller = ref.read(bookSearchProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: input,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            onChanged: controller.onInputChanged,
            onSubmitted: (value) {
              focus.unfocus();
              controller.submit(value);
            },
            decoration: InputDecoration(
              hintText: '搜索小说和漫画',
              isDense: true,
              filled: true,
              fillColor: colors.surfaceContainerHighest,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: !hasInput
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '清空',
                      onPressed: () {
                        input.clear();
                        controller.onInputChanged('');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _SearchModeChips(),
          const SizedBox(height: 10),
          const _SearchScopeToggle(),
          _SearchHistorySection(onUseKeyword: onUseKeyword),
          const _SearchPageLabel(),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _SearchModeChips extends ConsumerWidget {
  const _SearchModeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(bookSearchProvider.select((state) => state.mode));
    final controller = ref.read(bookSearchProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final entry in _modeLabels.entries) ...<Widget>[
            ChoiceChip(
              label: Text(entry.value, maxLines: 1, softWrap: false),
              selected: mode == entry.key,
              onSelected: (_) => controller.setMode(entry.key),
            ),
            if (entry.key != _modeLabels.keys.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SearchScopeToggle extends ConsumerWidget {
  const _SearchScopeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ref.watch(bookSearchProvider.select((state) => state.comic));
    // Column 给的是松约束，撑满宽度才和历史页的分段控件一致。
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: false, label: Text('小说')),
          ButtonSegment<bool>(value: true, label: Text('漫画')),
        ],
        selected: <bool>{comic},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            ref.read(bookSearchProvider.notifier).setComic(selection.first),
      ),
    );
  }
}

/// 页码提示。订阅的是渲染后的文案，翻页中间态不触发重建。
class _SearchPageLabel extends ConsumerWidget {
  const _SearchPageLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(
      bookSearchProvider.select((state) {
        if (state.isIdle || state.loading || state.error != null) return null;
        return '${state.comic ? '漫画' : '小说'} · 第 '
            '${state.page < 1 ? 1 : state.page} / '
            '${state.totalPages < 1 ? 1 : state.totalPages} 页';
      }),
    );
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SearchHistorySection extends ConsumerWidget {
  const _SearchHistorySection({required this.onUseKeyword});

  final void Function(String keyword) onUseKeyword;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idle = ref.watch(bookSearchProvider.select((state) => state.isIdle));
    if (!idle) return const SizedBox.shrink();
    final history = ref.watch(searchHistoryProvider).value;
    if (history == null || history.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '最近搜索',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '清除搜索历史',
                onPressed: ref.read(searchHistoryProvider.notifier).clear,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final keyword in history)
                InputChip(
                  label: Text(keyword),
                  onPressed: () => onUseKeyword(keyword),
                  onDeleted: () =>
                      ref.read(searchHistoryProvider.notifier).remove(keyword),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
