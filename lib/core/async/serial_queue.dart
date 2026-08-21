/// 串行任务队列：后一个任务等前一个结束再开始，避免并发写互相覆盖。
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// 队尾 future，完成时表示此前排队的任务已全部结束。
  Future<void> get idle => _tail;

  /// 异常只抛给调用方，队尾吞掉错误，不阻断后续任务。
  Future<T> add<T>(Future<T> Function() task) {
    final operation = _tail.then((_) => task());
    _tail = operation.then((_) {}, onError: (_) {});
    return operation;
  }
}
