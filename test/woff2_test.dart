import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/woff2.dart';

void main() {
  test('Native Assets 通过 libwoff2 输出 SFNT 字体', () {
    final input = File(
      '../Api/Api/wwwroot/font/5ef83ebe6e8d48bef185754627755b4b.woff2',
    ).readAsBytesSync();
    final output = decodeWoff2(input);

    expect(output.length, 3341444);
    expect(output.sublist(0, 4), <int>[0, 1, 0, 0]);
  });
}
