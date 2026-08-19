import 'main.dart' as app;
import 'dev/bench.dart';

/// 基准测试入口：正常启动 app，额外注册 `ext.lightnovel.bench`。
///
///   flutter run --profile -t lib/main_bench.dart
///
/// 正式包走 `lib/main.dart`，不会引用到 `dev/bench.dart`。
Future<void> main() async {
  registerBenchExtension();
  await app.main();
}
