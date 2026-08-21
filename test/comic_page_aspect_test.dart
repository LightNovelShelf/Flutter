import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';

void main() {
  test('整页比例取自地址上的 size，横跨两页的宽图不再按竖版占位', () {
    final image = ComicImage.decode(
      'https://img.example/page.webp?placeholder=LEHV6nWB2yk8&size=1600x1150',
    );
    expect(image.aspect, closeTo(1150 / 1600, 1e-9));
  });

  test('竖版单页比例大于 1', () {
    final image = ComicImage.decode(
      'https://img.example/page.webp?size=1000x1500',
    );
    expect(image.aspect, closeTo(1.5, 1e-9));
  });

  test('地址不带 size 时比例未知，交给调用方兜底', () {
    final image = ComicImage.decode(
      'https://img.example/page.webp?placeholder=LEHV6nWB2yk8',
    );
    expect(image.aspect, isNull);
  });

  test('size 取值非法时按未知处理', () {
    expect(
      ComicImage.decode('https://img.example/page.webp?size=0x1500').aspect,
      isNull,
    );
    expect(
      ComicImage.decode('https://img.example/page.webp?size=abc').aspect,
      isNull,
    );
  });
}
