import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/unread_counts.dart';
import '../shared/layout/adaptive_layout.dart';
import '../shared/widgets/unread_badge.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(communityUnreadCountProvider.notifier).reconcile());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  final GlobalKey _bodyKey = GlobalKey();

  void _goBranch(int index) => widget.shell.goBranch(
    index,
    initialLocation: index == widget.shell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final rail = useNavigationRail(MediaQuery.sizeOf(context));
    // 两侧各自成层：导航栏的 500ms 指示器动画不再连带重栅格整页内容。
    // 带 GlobalKey，窗口跨过断点换导航形态时各 tab 的页面状态跟着搬过去。
    final body = RepaintBoundary(key: _bodyKey, child: shell);
    if (!rail) {
      return Scaffold(
        body: body,
        bottomNavigationBar: RepaintBoundary(
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _goBranch,
            destinations: <Widget>[
              for (final item in _destinations)
                NavigationDestination(
                  icon: item.icon,
                  selectedIcon: item.selectedIcon,
                  label: item.label,
                ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RepaintBoundary(
            child: NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _goBranch,
              groupAlignment: 0,
              destinations: <NavigationRailDestination>[
                for (final item in _destinations)
                  NavigationRailDestination(
                    icon: item.icon,
                    selectedIcon: item.selectedIcon,
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: PaneMediaQuery(removeLeft: true, child: body)),
        ],
      ),
    );
  }
}

typedef _Destination = ({Widget icon, Widget selectedIcon, String label});

const List<_Destination> _destinations = <_Destination>[
  (
    icon: Icon(Icons.explore_outlined),
    selectedIcon: Icon(Icons.explore),
    label: '发现',
  ),
  (
    icon: Icon(Icons.collections_bookmark_outlined),
    selectedIcon: Icon(Icons.collections_bookmark),
    label: '书架',
  ),
  (
    icon: Icon(Icons.history_outlined),
    selectedIcon: Icon(Icons.history),
    label: '历史',
  ),
  (
    icon: _CommunityUnreadBadge(child: Icon(Icons.forum_outlined)),
    selectedIcon: _CommunityUnreadBadge(child: Icon(Icons.forum)),
    label: '社区',
  ),
  (
    icon: Icon(Icons.search_outlined),
    selectedIcon: Icon(Icons.search),
    label: '搜索',
  ),
];

/// 单独订阅未读数，避免资料刷新把整个 shell（连带 indexedStack 里所有 tab）标脏。
class _CommunityUnreadBadge extends ConsumerWidget {
  const _CommunityUnreadBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      UnreadBadge(count: ref.watch(communityUnreadCountProvider), child: child);
}
