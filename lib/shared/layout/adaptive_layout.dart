import 'package:flutter/widgets.dart';

/// 宽度达到这个值改用侧边导航栏，取 Material 3 的 medium 下界。
const double navigationRailMinWidth = 600;

/// 宽度达到这个值分成左右两栏，取 Material 3 的 expanded 下界。
const double twoPaneMinWidth = 840;

/// 侧边导航和分栏都要求窗口至少这么高，横放的手机（约 360~430 高）保持手机布局。
const double adaptiveMinHeight = 480;

/// 窗口是否用侧边导航栏代替底部导航栏。
bool useNavigationRail(Size window) =>
    window.width >= navigationRailMinWidth &&
    window.height >= adaptiveMinHeight;

/// [width] 宽的区域在当前窗口下是否分成左右两栏。高度看整个窗口，避免弹出键盘时退回单栏。
bool useTwoPane(double width, Size window) =>
    width >= twoPaneMinWidth && window.height >= adaptiveMinHeight;

/// 把子树 `MediaQuery.size` 的宽度改成实际分到的宽度，并去掉不贴屏幕边缘那一侧的安全区。
///
/// 页面里按 `MediaQuery.sizeOf` 算列数、气泡宽度的地方因此按所在栏计算。高度保持窗口高度，
/// 弹出键盘时 Scaffold 压缩的只是约束，断点判断不受影响。
class PaneMediaQuery extends StatelessWidget {
  const PaneMediaQuery({
    super.key,
    this.removeLeft = false,
    this.removeRight = false,
    required this.child,
  });

  final bool removeLeft;
  final bool removeRight;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inherited = MediaQuery.of(context);
      var media = inherited.copyWith(
        size: Size(constraints.maxWidth, inherited.size.height),
      );
      if (removeLeft || removeRight) {
        media = media
            .removePadding(removeLeft: removeLeft, removeRight: removeRight)
            .removeViewPadding(
              removeLeft: removeLeft,
              removeRight: removeRight,
            );
      }
      return MediaQuery(data: media, child: child);
    },
  );
}
