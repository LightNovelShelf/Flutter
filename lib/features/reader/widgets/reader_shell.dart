import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/state_views.dart';
import 'reader_paper_texture.dart';

/// 阅读器外壳：底色、加载与错误态、正文与叠层的层序。
///
/// [body] 在加载或出错时不会显示，正文未就绪的那一帧传占位即可。
class ReaderShell extends StatelessWidget {
  const ReaderShell({
    super.key,
    required this.background,
    this.paperTexture = false,
    this.loading = false,
    this.error,
    this.onRetry,
    required this.body,
    this.chrome,
    this.overlay,
  });

  final Color background;

  /// 纸质背景的纸纹，铺在正文之下。
  final bool paperTexture;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Widget body;

  /// 工具栏，自己按可见性淡入淡出，始终挂在最上层。
  final Widget? chrome;

  /// 正文之上、工具栏之下的常驻信息，需自带定位。
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final message = error;
    final Widget content;
    if (message != null) {
      // 出错时正文不在，工具栏只能靠点正文唤出，返回按钮是唯一的退出入口。
      content = ErrorStateView(
        message: message,
        onRetry: onRetry,
        onBack: context.canPop() ? context.pop : null,
      );
    } else if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = body;
    }
    // 自定义背景可以是任意颜色，状态栏与导航栏图标得跟着底色的明暗走，否则会看不见。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          children: <Widget>[
            if (paperTexture)
              const Positioned.fill(child: ReaderPaperTexture()),
            Positioned.fill(child: content),
            ?overlay,
            ?chrome,
          ],
        ),
      ),
    );
  }
}

/// 阅读器的加载态与请求版本。
///
/// 换章、重试、繁简切换会让多个请求同时在途，返回时按版本号丢弃过期的那些。
mixin ReaderLoadState<T extends StatefulWidget> on State<T> {
  int _version = 0;

  bool loading = true;
  String? loadError;

  /// 当前请求版本，供不另起版本的分批请求比对。
  int get requestVersion => _version;

  /// 开始一次新请求，返回它的版本号。
  int beginRequest() => ++_version;

  /// 结果已作废：组件卸载了，或有更晚的请求接手了。
  bool isStale(int version) => !mounted || version != _version;
}
