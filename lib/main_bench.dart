import 'main.dart' as app;
import 'dev/bench.dart';

/// 基准测试入口：启动 app 并注册 `ext.lightnovel.bench`，正式包走 `lib/main.dart`。
///
///   flutter run --profile -t lib/main_bench.dart
Future<void> main() async {
  registerBenchExtension();
  await app.main();
}
