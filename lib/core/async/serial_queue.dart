/// 串行任务队列：后一个任务等前一个结束再开始，避免并发写互相覆盖。
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// 队尾：等它完成即等到此前排队的任务全部落地。
  Future<void> get idle => _tail;

  /// 失败只交给调用方，队尾吞掉错误，后续任务照常排队。
  Future<T> add<T>(Future<T> Function() task) {
    final operation = _tail.then((_) => task());
    _tail = operation.then((_) {}, onError: (_) {});
    return operation;
  }
}
