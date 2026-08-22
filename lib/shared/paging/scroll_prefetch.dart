import 'package:flutter/material.dart';

const double kPrefetchThreshold = 480;

extension ScrollPrefetch on ScrollController {
  /// 距底部不足 [threshold] 逻辑像素就预取下一页。
  /// 同一份内容只请求一次：fling 期间每帧都会通知偏移变化，无条件回调会打出上百次请求。
  /// 内容长高（追加了新的一页）后 `maxScrollExtent` 变化，重新允许触发。
  /// 监听器随 controller 一起释放，无需单独 removeListener。
  void attachPrefetch({
    double threshold = kPrefetchThreshold,
    required VoidCallback onLoadMore,
  }) {
    double? requestedExtent;
    addListener(() {
      if (!hasClients) return;
      final ScrollPosition current = position;
      if (current.extentAfter >= threshold) {
        requestedExtent = null;
        return;
      }
      if (requestedExtent == current.maxScrollExtent) return;
      requestedExtent = current.maxScrollExtent;
      onLoadMore();
    });
  }
}

/// 触底预取：距底部不足 [threshold] 就回调一次。
/// 同一份内容只请求一次，`maxScrollExtent` 变化后重新放行；fling 期间每帧都会通知偏移变化。
/// 是否还有下一页由 [onLoadMore] 自己判断。
class PrefetchOnScroll extends StatefulWidget {
  const PrefetchOnScroll({
    super.key,
    this.threshold = kPrefetchThreshold,
    required this.onLoadMore,
    required this.child,
  });

  final double threshold;
  final VoidCallback onLoadMore;
  final Widget child;

  @override
  State<PrefetchOnScroll> createState() => _PrefetchOnScrollState();
}

class _PrefetchOnScrollState extends State<PrefetchOnScroll> {
  double? _requestedExtent;

  bool _onNotification(ScrollNotification notification) {
    final ScrollMetrics metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.extentAfter >= widget.threshold) {
      _requestedExtent = null;
      return false;
    }
    if (_requestedExtent == metrics.maxScrollExtent) return false;
    _requestedExtent = metrics.maxScrollExtent;
    widget.onLoadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}
