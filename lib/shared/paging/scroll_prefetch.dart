import 'package:flutter/material.dart';

extension ScrollPrefetch on ScrollController {
  /// 距底部不足 [threshold] 逻辑像素就预取下一页。
  /// 监听器随 controller 一起释放，页面不必单独 removeListener。
  void attachPrefetch({
    double threshold = 480,
    required VoidCallback onLoadMore,
  }) {
    addListener(() {
      if (!hasClients) return;
      if (position.extentAfter < threshold) onLoadMore();
    });
  }
}
