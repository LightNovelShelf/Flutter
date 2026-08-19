import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../data/api/decode.dart';
import '../shared/cover_seed.dart';

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

/// 造一份形状接近书目列表响应的 JSON，再 gzip，用来量解码链路。
Uint8List _gzippedPayload(int entries) {
  final list = <Map<String, Object?>>[
    for (var i = 0; i < entries; i++)
      <String, Object?>{
        'Id': i,
        'Title': '测试书名第$i卷 —— 很长的标题用来撑出真实的字节数',
        'Author': '作者$i',
        'Cover': 'https://example.invalid/cover/$i.jpg',
        'BlurHash': _hash,
        'Tags': <String>['轻小说', '奇幻', '日常'],
        'Intro': '简介' * 40,
      },
  ];
  return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(list))));
}

final Converter<List<int>, Object?> _utf8Json =
    const Utf8Decoder().fuse<Object?>(const JsonDecoder());

Object? _inflateJson(Uint8List bytes) => _utf8Json.convert(gzip.decode(bytes));

final Uint8List _payloadSmall = _gzippedPayload(12);
final Uint8List _payloadLarge = _gzippedPayload(400);

/// 96×144 的封面像素，取色链路的真实规模。
final Uint8List _coverPixels = () {
  final bytes = Uint8List(96 * 144 * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = (i * 7) & 0xff;
    bytes[i + 1] = (i * 13) & 0xff;
    bytes[i + 2] = (i * 29) & 0xff;
    bytes[i + 3] = 0xff;
  }
  return bytes;
}();

final Map<String, Future<void> Function()> _cases =
    <String, Future<void> Function()>{
  // 封面占位图解码：改动前 32×48，改动后 16×24。实测 1502µs vs 378µs。
  'blurhash_32x48': () async =>
      _consume(await blurHashDecode(blurHash: _hash, width: 32, height: 48)),
  'blurhash_16x24': () async =>
      _consume(await blurHashDecode(blurHash: _hash, width: 16, height: 24)),
  // BlurHash 校验：每条书目解析都要跑一次。
  'base83_normalize': () async => _consume(normalizeBlurHash(_hash)),
  // 解压 + 解析：gzip 响应的解码链路。
  'inflate_small': () async => _consume(_inflateJson(_payloadSmall)),
  'inflate_large': () async => _consume(_inflateJson(_payloadLarge)),
  // 封面取色：量化是 k-means，跑在后台 isolate 上。
  'coverseed': () async => _consume(await seedColorFromRawRgba(_coverPixels)),
};
