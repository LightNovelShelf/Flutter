import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// 从封面取一个适合当主题种子的颜色。
///
/// 用 Material 3 的量化与打分算法（`QuantizerCelebi` + `Score`）挑选。
Future<Color?> resolveCoverSeedColor(
  ImageProvider<Object> provider, {
  required Size size,
  int maximumColorCount = 8,
}) async {
  final image = await _decodeScaled(provider, size);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return await seedColorFromRawRgba(
      data.buffer.asUint8List(),
      maximumColorCount: maximumColorCount,
    );
  } finally {
    image.dispose();
  }
}

/// `rawRgba` 四字节一像素，全透明像素不参与统计；所有颜色都不适合当 seed 时退回
/// 出现最多的那个，而不是 `Score` 内置的兜底色。
///
/// 量化是 k-means，整段放在 [Isolate.run] 上执行。
Future<Color?> seedColorFromRawRgba(
  Uint8List bytes, {
  int maximumColorCount = 8,
}) async {
  final argb = await Isolate.run(
    () => _seedArgbFromRawRgba(bytes, maximumColorCount),
  );
  return argb == null ? null : Color(argb);
}

Future<int?> _seedArgbFromRawRgba(Uint8List bytes, int maximumColorCount) async {
  // 预分配到像素数上限，避免 growable List 反复扩容。
  final packed = Uint32List(bytes.length ~/ 4);
  var count = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final alpha = bytes[i + 3];
    if (alpha == 0) continue;
    packed[count++] =
        (alpha << 24) | (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
  }
  if (count == 0) return null;

  final quantized = await QuantizerCelebi().quantize(
    Uint32List.sublistView(packed, 0, count),
    maximumColorCount,
  );
  final counts = quantized.colorToCount;
  if (counts.isEmpty) return null;
  final best = Score.score(counts, desired: 1).first;
  // Score 的返回值取自输入色；不在输入里说明它落到了内置兜底色。
  if (counts.containsKey(best)) return best;
  final dominant = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return dominant.key;
}

Future<ui.Image> _decodeScaled(ImageProvider<Object> provider, Size size) {
  final resized = ResizeImage(
    provider,
    width: size.width.round(),
    height: size.height.round(),
    allowUpscaling: false,
  );
  final completer = Completer<ui.Image>();
  final stream = resized.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
