import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 长列表视口上下各预建一屏。
///
/// 一屏以内来回滚动的条目一直挂在树上，图层原样复用，只平移不重建、不重绘；
/// 更远的条目在离视口一屏处就构建并开始解码图片，进入视口时已经就绪。
const ScrollCacheExtent listCacheExtent = ScrollCacheExtent.viewport(1);

/// 滚动视图里的单个盒子，内容隔离成独立图层。
///
/// 视口每个滚动帧都会重绘所有可见 sliver。`SliverList` / `SliverGrid` 的条目自带
/// [RepaintBoundary]，[SliverToBoxAdapter] 没有，不隔离的话里面的内容每帧重录一遍。
class SliverLayer extends StatelessWidget {
  const SliverLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: RepaintBoundary(child: child));
}
