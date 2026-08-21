import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import '../shared/widgets/blurhash_image.dart';

import '../data/api/decode.dart';
import '../shared/cover_seed.dart';

/// 真机方法级基准台，只在 `lib/main_bench.dart` 入口注册。
///
/// profile 模式是 AOT，VM Service 的 `evaluate` 不可用，改为在 app 内注册 service
/// extension，由外部调用触发设备上的循环，测到的是 AOT 代码开销。
///
/// 用法（外部通过 VM Service 调用，见 tool/bench.ts）：
///   ext.lightnovel.bench                              → 列出所有用例
///   ext.lightnovel.bench?case=X&iterations=N&rounds=R → 跑用例
void registerBenchExtension() {
  registerExtension('ext.lightnovel.bench', (
    String method,
    Map<String, String> params,
  ) async {
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

    // 预热，让 AOT 的 inline cache 稳定并排除首次分配的堆增长。
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
        // 消费结果，否则 AOT 可能把被测调用当死代码删除。
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

/// 构造接近书目列表响应的 JSON 并 gzip，用于测量解码链路。
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

final Converter<List<int>, Object?> _utf8Json = const Utf8Decoder()
    .fuse<Object?>(const JsonDecoder());

Object? _inflateJson(Uint8List bytes) => _utf8Json.convert(gzip.decode(bytes));

final Uint8List _payloadSmall = _gzippedPayload(12);
final Uint8List _payloadLarge = _gzippedPayload(400);

/// 96×144 封面像素，与取色链路的实际输入规模一致。
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
      // 封面占位图本机查表解码。
      'blurhash_32x48': () async =>
          _consume(decodeBlurHash(_hash, width: 32, height: 48)),
      'blurhash_16x24': () async =>
          _consume(decodeBlurHash(_hash, width: 16, height: 24)),
      // BlurHash 校验：每条书目解析都要跑一次。
      'base83_normalize': () async => _consume(normalizeBlurHash(_hash)),
      // 解压 + 解析：gzip 响应的解码链路。
      'inflate_small': () async => _consume(_inflateJson(_payloadSmall)),
      'inflate_large': () async => _consume(_inflateJson(_payloadLarge)),
      // 封面取色：量化是 k-means，跑在后台 isolate 上。
      'coverseed': () async =>
          _consume(await seedColorFromRawRgba(_coverPixels)),
    };
