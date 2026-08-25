import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_comic_paging.dart';

/// 竖版单页与横跨两页的宽图。
const double _portrait = 1.5;
const double _wide = 0.625;

void main() {
  test('竖版页两两成对', () {
    expect(
      createComicSpreads(const <double>[
        _portrait,
        _portrait,
        _portrait,
        _portrait,
      ]),
      <List<int>>[
        <int>[0, 1],
        <int>[2, 3],
      ],
    );
  });

  test('页数为奇数时最后一页落单', () {
    expect(
      createComicSpreads(const <double>[_portrait, _portrait, _portrait]),
      <List<int>>[
        <int>[0, 1],
        <int>[2],
      ],
    );
  });

  test('宽图独占一屏，并把后面的配对错开一位', () {
    expect(
      createComicSpreads(const <double>[
        _portrait,
        _portrait,
        _portrait,
        _wide,
        _portrait,
        _portrait,
      ]),
      <List<int>>[
        <int>[0, 1],
        // 下一页是宽图，配不上对，这一页自己占一屏。
        <int>[2],
        <int>[3],
        <int>[4, 5],
      ],
    );
  });

  test('连着两张宽图各占一屏', () {
    expect(createComicSpreads(const <double>[_wide, _wide]), <List<int>>[
      <int>[0],
      <int>[1],
    ]);
  });

  test('没有页时没有屏', () {
    expect(createComicSpreads(const <double>[]), isEmpty);
  });

  test('页码反查所在的屏', () {
    final spreads = createComicSpreads(const <double>[
      _portrait,
      _portrait,
      _wide,
      _portrait,
      _portrait,
    ]);
    expect(createComicSpreadIndex(spreads, 5), <int>[0, 0, 1, 2, 2]);
  });
}
