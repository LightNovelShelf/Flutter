import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/app_sheet.dart';

const int signMakeupWindowDays = 30;

bool canUseSignMakeupCard({
  required DateTime date,
  required DateTime today,
  required int cards,
  required bool signed,
}) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final todayUtc = DateTime.utc(today.year, today.month, today.day);
  final floor = todayUtc.subtract(const Duration(days: signMakeupWindowDays));
  return cards > 0 && !signed && day.isBefore(todayUtc) && !day.isBefore(floor);
}

String formatSignDateUtc(DateTime date) =>
    date.toUtc().toIso8601String().substring(0, 10);

Future<void> showSignInSheet(BuildContext context) async {
  await showDraggableSheet<void>(
    context,
    initialSize: 0.78,
    minSize: 0.6,
    showDragHandle: true,
    builder: (_, controller) => _SignInSheet(scrollController: controller),
  );
}

class _SignInSheet extends ConsumerStatefulWidget {
  const _SignInSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<_SignInSheet> {
  static const List<String> _weekLabels = <String>[
    '日',
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
  ];

  late final DateTime _today;
  late int _year;
  late int _month;
  Set<int> _signedDays = <int>{};
  int _makeupCards = 0;
  bool _loading = true;
  bool _calendarLoading = false;
  bool _signing = false;
  int? _makingUpDay;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _today = DateTime.utc(now.year, now.month, now.day);
    _year = _today.year;
    _month = _today.month;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final calendarFuture = api.getSignInCalendar(year: _year, month: _month);
      final inventoryFuture = api.getMyItems();
      final calendar = await calendarFuture;
      final inventory = await inventoryFuture;
      if (!mounted) return;
      setState(() {
        _signedDays = calendar.days.map((day) => day.day).nonNulls.toSet();
        _makeupCards =
            inventory.items
                .where((item) => item.key == signMakeupItemKey)
                .map((item) => item.quantity)
                .firstOrNull ??
            0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = describeApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCalendar() async {
    setState(() {
      _calendarLoading = true;
      _error = null;
    });
    try {
      final calendar = await ref
          .read(apiClientProvider)
          .getSignInCalendar(year: _year, month: _month);
      if (!mounted) return;
      setState(
        () =>
            _signedDays = calendar.days.map((day) => day.day).nonNulls.toSet(),
      );
    } catch (error) {
      if (mounted) setState(() => _error = describeApiError(error));
    } finally {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  void _shiftMonth(int delta) {
    final shifted = DateTime.utc(_year, _month + delta, 1);
    setState(() {
      _year = shifted.year;
      _month = shifted.month;
    });
    unawaited(_loadCalendar());
  }

  Future<void> _signIn() async {
    if (_signing) return;
    setState(() => _signing = true);
    try {
      final result = await ref.read(profileProvider.notifier).checkIn();
      await _loadCalendar();
      if (!mounted) return;
      _showMessage('签到成功，连签 ${result.streak} 天');
    } catch (error) {
      if (mounted) _showMessage(describeApiError(error), error: true);
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _makeUp(int day) async {
    if (_makingUpDay != null) return;
    final date = DateTime.utc(_year, _month, day);
    final dateText = formatSignDateUtc(date);
    final confirmed = await showAppConfirm(
      context: context,
      title: '使用补签卡',
      message: '消耗 1 张补签卡补签 $dateText？',
      confirmLabel: '确认补签',
    );
    if (!confirmed || !mounted) return;

    setState(() => _makingUpDay = day);
    try {
      final result = await ref
          .read(apiClientProvider)
          .useSignMakeupCard(date: dateText);
      await ref.read(profileProvider.notifier).reload();
      if (!mounted) return;
      setState(() => _makeupCards = result.owned);
      await _loadCalendar();
      if (!mounted) return;
      _showMessage('补签成功，当天连签 ${result.streak} 天');
    } catch (error) {
      if (mounted) _showMessage(describeApiError(error), error: true);
    } finally {
      if (mounted) setState(() => _makingUpDay = null);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? colors.error : null,
      ),
    );
  }

  bool get _canGoPrev {
    final monthStart = DateTime.utc(_year, _month, 1);
    final floor = _today.subtract(const Duration(days: signMakeupWindowDays));
    return monthStart.isAfter(floor);
  }

  bool get _canGoNext => DateTime.utc(
    _year,
    _month,
    1,
  ).isBefore(DateTime.utc(_today.year, _today.month, 1));

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final growth = profile?.growth;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SheetHeader(icon: Icons.event_available_outlined, title: '每日签到'),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '连续签到 ${growth?.signInStreak ?? 0} 天',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '每日签到累积经验，连签有额外奖励',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: growth == null || growth.signedToday || _signing
                        ? null
                        : _signIn,
                    child: _signing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(growth?.signedToday == true ? '今日已签到' : '签到'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '补签卡 $_makeupCards 张 · 点漏签日即可补签',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      unawaited(router.push('/shop'));
                    },
                    child: const Text('去商城'),
                  ),
                ],
              ),
              if (_loading || _calendarLoading)
                const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(_error!)),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: '上个月',
                    onPressed: _canGoPrev && !_calendarLoading
                        ? () => _shiftMonth(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      '$_year 年 $_month 月（UTC）',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    onPressed: _canGoNext && !_calendarLoading
                        ? () => _shiftMonth(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  for (final label in _weekLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _buildCalendar(colors),
              const SizedBox(height: 12),
              Text(
                '描边日期是最近 $signMakeupWindowDays 天内可补签的漏签日，补签后连续天数按结果重算。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar(ColorScheme colors) {
    final firstWeekday = DateTime.utc(_year, _month, 1).weekday % 7;
    final daysInMonth = DateTime.utc(_year, _month + 1, 0).day;
    final cellCount = firstWeekday + daysInMonth;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      itemCount: cellCount,
      itemBuilder: (context, index) {
        if (index < firstWeekday) return const SizedBox.shrink();
        final day = index - firstWeekday + 1;
        final date = DateTime.utc(_year, _month, day);
        final signed = _signedDays.contains(day);
        final today = date == _today;
        final canMakeUp = canUseSignMakeupCard(
          date: date,
          today: _today,
          cards: _makeupCards,
          signed: signed,
        );
        final busy = _makingUpDay == day;
        final border = today
            ? Border.all(color: colors.secondary, width: 2)
            : canMakeUp
            ? Border.all(color: colors.tertiary, width: 1.5)
            : null;

        return Center(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: canMakeUp && _makingUpDay == null
                ? () => _makeUp(day)
                : null,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: signed ? colors.primary : null,
                border: border,
              ),
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '$day',
                      style: TextStyle(
                        color: signed ? colors.onPrimary : colors.onSurface,
                        fontWeight: today ? FontWeight.w700 : null,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
