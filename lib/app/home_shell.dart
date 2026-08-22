import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/profile_repository.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 两侧各自成层：NavigationBar 的 500ms 指示器动画不再连带重栅格整页内容。
      body: RepaintBoundary(child: shell),
      bottomNavigationBar: RepaintBoundary(
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: '发现',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark),
              label: '书架',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: '历史',
            ),
            NavigationDestination(
              icon: _UnreadBadge(child: Icon(Icons.forum_outlined)),
              selectedIcon: _UnreadBadge(child: Icon(Icons.forum)),
              label: '社区',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: '搜索',
            ),
          ],
        ),
      ),
    );
  }
}

/// 单独订阅未读数，避免资料刷新把整个 shell（连带 indexedStack 里所有 tab）标脏。
class _UnreadBadge extends ConsumerWidget {
  const _UnreadBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      profileProvider.select(
        (profile) => profile.value?.unreadNotificationCount ?? 0,
      ),
    );
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: child,
    );
  }
}
