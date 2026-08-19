import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// 从封面里取一个适合当主题种子的颜色。
///
/// 用的是 Material 3 自己的量化 + 打分算法（`QuantizerCelebi` + `Score`），
/// 它挑的就是「适合做 seed」的颜色，比按 vibrant/dominant/muted 分档更贴近用途。
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

/// `rawRgba` 是四字节一像素；全透明像素不参与统计。
/// 所有颜色都不适合当 seed 时（例如纯灰阶封面），退回出现最多的那个，
/// 而不是 `Score` 内置的 Google Blue 兜底色。
Future<Color?> seedColorFromRawRgba(
  Uint8List bytes, {
  int maximumColorCount = 8,
}) async {
  final pixels = <int>[];
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final alpha = bytes[i + 3];
    if (alpha == 0) continue;
    pixels.add(
      (alpha << 24) | (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
    );
  }
  if (pixels.isEmpty) return null;

  final quantized = await QuantizerCelebi().quantize(
    pixels,
    maximumColorCount,
  );
  final counts = quantized.colorToCount;
  if (counts.isEmpty) return null;
  final best = Score.score(counts, desired: 1).first;
  // Score 的返回值取自输入色；不在输入里说明它落到了内置兜底色。
  if (counts.containsKey(best)) return Color(best);
  final dominant = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return Color(dominant.key);
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
