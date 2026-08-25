import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 沉浸式阅读只有 Android 支持。
bool get readerImmersiveSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 沉浸式阅读：阅读器在场且设置开启时藏起状态栏与导航栏，离场再还回去。
///
/// 只有 Android 有 [SystemUiMode.immersiveSticky]，其它平台整个组件不作为。
class ReaderImmersiveMode extends StatefulWidget {
  const ReaderImmersiveMode({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<ReaderImmersiveMode> createState() => _ReaderImmersiveModeState();
}

class _ReaderImmersiveModeState extends State<ReaderImmersiveMode>
    with WidgetsBindingObserver {
  bool _attached = false;

  bool get _enabled => widget.enabled;

  @override
  void initState() {
    super.initState();
    if (!readerImmersiveSupported) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _ReaderImmersiveController.instance.attach(this);
  }

  @override
  void didUpdateWidget(ReaderImmersiveMode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attached && oldWidget.enabled != widget.enabled) {
      _ReaderImmersiveController.instance.refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时系统栏可能已经被系统还原，重新下发一次。
    if (state == AppLifecycleState.resumed) {
      _ReaderImmersiveController.instance.reapply();
    }
  }

  @override
  void dispose() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _ReaderImmersiveController.instance.detach(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 汇总在场的阅读器，只要有一个要沉浸就藏起系统栏。
///
/// 阅读器之间可以互相叠放（跨章跳转、书籍互链），按实例数判断比各自下发可靠。
class _ReaderImmersiveController {
  _ReaderImmersiveController._();

  static final _ReaderImmersiveController instance =
      _ReaderImmersiveController._();

  final List<_ReaderImmersiveModeState> _listeners =
      <_ReaderImmersiveModeState>[];

  /// 当前是否由我们藏着系统栏；没藏过就不去动系统栏，免得改掉别处的设置。
  bool _hidden = false;

  void attach(_ReaderImmersiveModeState listener) {
    _listeners.add(listener);
    refresh();
  }

  void detach(_ReaderImmersiveModeState listener) {
    _listeners.remove(listener);
    refresh();
  }

  void refresh() {
    final hidden = _listeners.any((listener) => listener._enabled);
    if (_hidden == hidden) return;
    _hidden = hidden;
    _apply();
  }

  /// 状态没变但系统栏可能被动过，照当前状态再发一次。
  void reapply() {
    if (!_hidden) return;
    _apply();
  }

  void _apply() {
    SystemChrome.setEnabledSystemUIMode(
      // immersiveSticky：从边缘划出的系统栏会自己退回去，不用手动收。
      _hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
