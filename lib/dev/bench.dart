import 'dart:convert';
import 'dart:developer';

import 'package:flutter_blurhash/flutter_blurhash.dart';

/// 真机方法级基准台。只在 `lib/main_bench.dart` 入口里注册，正式包不会引用到这里。
///
/// profile 模式是 AOT，VM Service 的 `evaluate` 不可用，所以只能反过来：app 里挂一个
/// service extension，外部调它、它在设备上跑循环。测出来的是 AOT 代码的真实开销。
///
/// 用法（外部通过 VM Service 调用，见 tool/bench.ts）：
///   ext.lightnovel.bench                              → 列出所有用例
///   ext.lightnovel.bench?case=X&iterations=N&rounds=R → 跑用例
void registerBenchExtension() {
  registerExtension('ext.lightnovel.bench', (String method, Map<String, String> params) async {
    final String? name = params['case'];
    if (name == null) {
      return ServiceExtensionResponse.result(
        jsonEncode(<String, Object>{'cases': _cases.keys.toList()}),
      );
    }
    final Future<void> Function()? body = _cases[name];
    if (body == null) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams,
        'unknown case: $name (have ${_cases.keys.join(', ')})',
      );
    }
    final int iterations = int.tryParse(params['iterations'] ?? '') ?? 200;
    final int rounds = int.tryParse(params['rounds'] ?? '') ?? 5;

    // 预热：让 AOT 的 inline cache 稳定下来，也把首次分配的堆增长排除掉。
    for (var i = 0; i < iterations; i++) {
      await body();
    }
    final List<int> elapsed = <int>[];
    for (var r = 0; r < rounds; r++) {
      final Stopwatch sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        await body();
      }
      sw.stop();
      elapsed.add(sw.elapsedMicroseconds);
    }
    elapsed.sort();
    final int medianUs = elapsed[elapsed.length ~/ 2];
    return ServiceExtensionResponse.result(
      jsonEncode(<String, Object>{
        'case': name,
        'iterations': iterations,
        'rounds': rounds,
        'medianUs': medianUs,
        'minUs': elapsed.first,
        'maxUs': elapsed.last,
        'usPerOp': medianUs / iterations,
        // 把结果消费掉，否则 AOT 可能把整个调用当死代码删掉，测出 0。
        'sink': _sink,
      }),
    );
  });
}

int _sink = 0;

void _consume(Object? value) {
  // 必须用 identityHashCode：深比较的 hashCode（如 ThemeData）会把消费开销算进被测方法。
  _sink = (_sink ^ identityHashCode(value)) & 0x3fffffff;
}

const String _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

final Map<String, Future<void> Function()> _cases =
    <String, Future<void> Function()>{
  // 封面占位图解码：改动前 32×48，改动后 16×24。实测 1502µs vs 378µs。
  'blurhash_32x48': () async =>
      _consume(await blurHashDecode(blurHash: _hash, width: 32, height: 48)),
  'blurhash_16x24': () async =>
      _consume(await blurHashDecode(blurHash: _hash, width: 16, height: 24)),
};
