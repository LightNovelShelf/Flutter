import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/layout/adaptive_layout.dart';
import 'pane_routes.dart';

/// 详情栏还没有内容时显示的提示。
class PanePlaceholder {
  const PanePlaceholder({required this.icon, required this.message});

  final IconData icon;
  final String message;

  static const PanePlaceholder book = PanePlaceholder(
    icon: Icons.auto_stories_outlined,
    message: '选择一本书查看详情',
  );

  static const PanePlaceholder announcement = PanePlaceholder(
    icon: Icons.campaign_outlined,
    message: '选择一条公告查看详情',
  );

  static const PanePlaceholder settings = PanePlaceholder(
    icon: Icons.tune,
    message: '选择左侧的设置项',
  );
}

/// 宽屏下把页面分成左右两栏：左栏是 [child]，右栏是独立的详情导航栈。
///
/// 左栏里用 [PaneNavigation.openPage] 打开 [buildPanePage] 认得的地址会换掉右栏内容，
/// 右栏里再打开则叠在右栏栈上；其余地址照常整页打开。窄屏时只显示 [child]。
class ListDetailHost extends StatefulWidget {
  const ListDetailHost({
    super.key,
    required this.child,
    this.placeholder = PanePlaceholder.book,
    this.initialLocation,
    this.primaryFraction = 0.5,
  });

  final Widget child;
  final PanePlaceholder placeholder;

  /// 右栏的常驻底页，设置后不再显示 [placeholder]。必须是 [buildPanePage] 认得的地址。
  final String? initialLocation;

  /// 左栏占总宽的比例。
  final double primaryFraction;

  @override
  State<ListDetailHost> createState() => _ListDetailHostState();
}

class _PaneEntry {
  _PaneEntry(this.id, this.location, this.page);

  final int id;
  final String location;
  final Widget page;
}

class _ListDetailHostState extends State<ListDetailHost> {
  static const double _minPrimaryWidth = 320;
  static const double _minDetailWidth = 420;

  final List<_PaneEntry> _entries = <_PaneEntry>[];
  int _nextId = 0;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _twoPane = false;

  int get _base => widget.initialLocation == null ? 0 : 1;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLocation;
    if (initial != null) {
      _entries.add(_entry(initial, buildPanePage(Uri.parse(initial))!));
    }
  }

  _PaneEntry _entry(String location, Widget page) =>
      _PaneEntry(_nextId++, location, page);

  void _select(String location, Widget page) {
    if (_entries.length == _base + 1 && _entries.last.location == location) {
      return;
    }
    setState(() {
      _entries
        ..removeRange(_base, _entries.length)
        ..add(_entry(location, page));
    });
  }

  void _push(String location, Widget page) =>
      setState(() => _entries.add(_entry(location, page)));

  void _replace(String location, Widget page) => setState(() {
    if (_entries.length > _base) _entries.removeLast();
    _entries.add(_entry(location, page));
  });

  bool _dismiss() {
    if (_entries.length <= _base) return false;
    setState(_entries.removeLast);
    return true;
  }

  void _onDidRemovePage(Page<Object?> page) {
    final index = _entries.indexWhere(
      (entry) => ValueKey<int>(entry.id) == page.key,
    );
    if (index >= 0) setState(() => _entries.removeAt(index));
  }

  /// 收成单栏时，正在显示的那一栏把详情栈按顺序整页推出去，免得旋转屏幕后内容消失。
  /// 不可见的分支（其它 tab、被盖住的页面）留着详情栈，再展开时原样显示。
  void _syncMode(bool twoPane) {
    if (twoPane == _twoPane) return;
    final collapsing = _twoPane;
    _twoPane = twoPane;
    if (!collapsing ||
        _entries.length <= _base ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    final moved = <String>[
      for (final entry in _entries.skip(_base)) entry.location,
    ];
    _entries.removeRange(_base, _entries.length);
    final router = GoRouter.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final location in moved) {
        router.push(location);
      }
    });
  }

  double _primaryWidth(double width) => math
      .min(
        math.max(width * widget.primaryFraction, _minPrimaryWidth),
        width - _minDetailWidth,
      )
      .floorToDouble();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final twoPane = useTwoPane(width, MediaQuery.sizeOf(context));
      _syncMode(twoPane);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 左栏始终是第一个同类型孩子，单双栏切换时页面状态不丢。
          SizedBox(
            width: twoPane ? _primaryWidth(width) : width,
            child: _PaneScope(
              host: this,
              active: twoPane,
              detail: false,
              child: PaneMediaQuery(removeRight: twoPane, child: widget.child),
            ),
          ),
          if (twoPane) ...<Widget>[
            const VerticalDivider(width: 1),
            Expanded(
              child: _PaneScope(
                host: this,
                active: true,
                detail: true,
                child: PaneMediaQuery(
                  removeLeft: true,
                  // 右栏的 Scaffold 自成一组：提示条只出现在发起的那一栏，不会两栏各弹一条。
                  child: ScaffoldMessenger(child: ClipRect(child: _detail())),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );

  Widget _detail() {
    if (_entries.isEmpty) {
      return _PanePlaceholderView(placeholder: widget.placeholder);
    }
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: _navigatorKey,
        pages: <Page<Object?>>[
          for (final entry in _entries)
            MaterialPage<Object?>(
              key: ValueKey<int>(entry.id),
              name: entry.location,
              child: entry.page,
            ),
        ],
        onDidRemovePage: _onDidRemovePage,
      ),
    );
  }
}

class _PaneScope extends InheritedWidget {
  const _PaneScope({
    required this.host,
    required this.active,
    required this.detail,
    required super.child,
  });

  final _ListDetailHostState host;
  final bool active;

  /// 是否位于右栏。
  final bool detail;

  @override
  bool updateShouldNotify(_PaneScope oldWidget) =>
      host != oldWidget.host ||
      active != oldWidget.active ||
      detail != oldWidget.detail;
}

class _PanePlaceholderView extends StatelessWidget {
  const _PanePlaceholderView({required this.placeholder});

  final PanePlaceholder placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 用 Scaffold 承载，右栏页面关掉后留下的提示条仍有地方显示。
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(placeholder.icon, size: 48, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              placeholder.message,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页面跳转统一走这里，双栏时自动落到右栏。
extension PaneNavigation on BuildContext {
  _PaneScope? get _activePane {
    final scope = getInheritedWidgetOfExactType<_PaneScope>();
    return scope != null && scope.active ? scope : null;
  }

  /// 双栏且 [location] 能放进右栏时在右栏打开，否则等同 `push`。
  Future<T?> openPage<T extends Object?>(String location) {
    final scope = _activePane;
    final page = scope == null ? null : buildPanePage(Uri.parse(location));
    if (scope == null || page == null) return push<T>(location);
    scope.detail
        ? scope.host._push(location, page)
        : scope.host._select(location, page);
    return Future<T?>.value();
  }

  /// 双栏且 [location] 能放进右栏时替换右栏当前页，否则等同 `pushReplacement`。
  void replacePage(String location) {
    final scope = _activePane;
    final page = scope == null ? null : buildPanePage(Uri.parse(location));
    if (scope == null || page == null) {
      pushReplacement(location);
      return;
    }
    scope.detail
        ? scope.host._replace(location, page)
        : scope.host._select(location, page);
  }

  /// 在右栏里时关掉右栏当前页并返回 true；不在右栏里返回 false。
  bool closePanePage() {
    final scope = _activePane;
    return scope != null && scope.detail && scope.host._dismiss();
  }
}
