import 'package:flutter/widgets.dart';

/// 身份守卫的 sliver 子节点 delegate：列表实例与 revision 不变就不重建已建子节点。
///
/// `SliverList.builder` / `SliverGrid.builder` 每次父级 build 都会造一个默认必定重建的 delegate。
class IdentityChildDelegate<T> extends SliverChildBuilderDelegate {
  IdentityChildDelegate({
    required this.items,
    required Widget Function(BuildContext context, T item, int index)
    itemBuilder,
    this.revision,
    this.trailingCount = 0,
    IndexedWidgetBuilder? trailingBuilder,
    this.comparePrefix = false,
  }) : super(
         (context, index) => index < items.length
             ? itemBuilder(context, items[index], index)
             : trailingBuilder?.call(context, index - items.length),
         childCount: items.length + trailingCount,
         addAutomaticKeepAlives: false,
       );

  final List<T> items;

  /// 列表实例之外还要比较的标量，多个用 record 打包。
  final Object? revision;

  final int trailingCount;

  /// 逐项比较列表实例相同的前缀。返回 false 也会跳过 sliver 重排，
  /// 只有依赖重排揭示追加子节点的调用方才需要打开。
  final bool comparePrefix;

  @override
  bool shouldRebuild(covariant IdentityChildDelegate<T> oldDelegate) {
    if (revision != oldDelegate.revision ||
        trailingCount != oldDelegate.trailingCount) {
      return true;
    }
    if (identical(items, oldDelegate.items)) return false;
    if (!comparePrefix) return true;
    if (items.length < oldDelegate.items.length) return true;
    for (var i = 0; i < oldDelegate.items.length; i++) {
      if (!identical(items[i], oldDelegate.items[i])) return true;
    }
    return false;
  }
}
