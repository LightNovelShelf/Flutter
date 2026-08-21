import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:lightnovel/shared/cover_seed.dart';

/// 构造 rawRgba 像素数据，`colors` 按顺序每种各占 `repeat` 个像素。
Uint8List _rawRgba(List<Color> colors, {int repeat = 64}) {
  final bytes = Uint8List(colors.length * repeat * 4);
  var i = 0;
  for (final color in colors) {
    for (var n = 0; n < repeat; n++) {
      bytes[i++] = (color.r * 255).round();
      bytes[i++] = (color.g * 255).round();
      bytes[i++] = (color.b * 255).round();
      bytes[i++] = (color.a * 255).round();
    }
  }
  return bytes;
}

double _hue(Color color) => Hct.fromInt(color.toARGB32()).hue;

void main() {
  group('封面取色', () {
    test('挑出彩度高的主色，而不是背景大面积的灰白', () async {
      final seed = await seedColorFromRawRgba(
        _rawRgba(<Color>[
          const Color(0xFFF5F5F5),
          const Color(0xFFF5F5F5),
          const Color(0xFFF5F5F5),
          const Color(0xFFD81B60),
        ]),
      );

      expect(seed, isNotNull);
      // 洋红附近（Hct 色相约 0~30），不能是灰白。
      expect(Hct.fromInt(seed!.toARGB32()).chroma, greaterThan(20));
      expect((_hue(seed) - _hue(const Color(0xFFD81B60))).abs(), lessThan(25));
    });

    test('纯灰阶封面退回占比最高的颜色，而不是内置蓝色兜底', () async {
      final seed = await seedColorFromRawRgba(
        _rawRgba(<Color>[
          const Color(0xFF9E9E9E),
          const Color(0xFF9E9E9E),
          const Color(0xFF9E9E9E),
          const Color(0xFF424242),
        ]),
      );

      expect(seed, isNotNull);
      expect(Hct.fromInt(seed!.toARGB32()).chroma, lessThan(5));
      // Score 的兜底色是 Google Blue（0xFF4285F4），此处不应命中。
      expect(seed.toARGB32(), isNot(0xFF4285F4));
    });

    test('全透明像素不参与统计', () async {
      final seed = await seedColorFromRawRgba(
        _rawRgba(<Color>[const Color(0x00000000)]),
      );

      expect(seed, isNull);
    });
  });
}
