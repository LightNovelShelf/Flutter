import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/image_sizing.dart';

/// 图床按尺寸取图的客户端约定。
///
/// 图床只接受 256 的整倍数，其它值原样返回未缩放的图，因此客户端只发合法档位。
void main() {
  group('imageHeightBucketFor', () {
    test('永远是 256 的正整数倍', () {
      for (var logical = 1.0; logical <= 1200; logical += 7) {
        for (final dpr in <double>[1, 1.5, 2, 2.625, 3, 3.5, 4]) {
          final bucket = imageHeightBucketFor(logical, dpr);
          expect(bucket % imageHeightStep, 0, reason: '$logical @$dpr');
          expect(bucket, greaterThan(0));
        }
      }
    });

    test('就近取档而非向上取整', () {
      // 531px（PLC110 竖屏封面）落到 512，而不是越过图片自身高度的 768。
      expect(imageHeightBucketFor(151.71, 3.5), 512);
      expect(imageHeightBucketFor(383, 1), 256);
      expect(imageHeightBucketFor(385, 1), 512);
    });

    test('小图与非法输入都收敛到最小档', () {
      expect(imageHeightBucketFor(48, 1), imageHeightStep);
      expect(imageHeightBucketFor(0, 3), imageHeightStep);
      expect(imageHeightBucketFor(-10, 3), imageHeightStep);
      expect(imageHeightBucketFor(double.nan, 3), imageHeightStep);
      expect(imageHeightBucketFor(double.infinity, 3), imageHeightStep);
    });

    test('超大尺寸封顶，避免把缓存键打散', () {
      expect(imageHeightBucketFor(9000, 4), maxImageHeightRequest);
    });
  });

  group('withImageHeight', () {
    test('无查询串时新起一个', () {
      expect(
        withImageHeight('https://img.example/a.webp', 512),
        'https://img.example/a.webp?height=512',
      );
    });

    test('保留地址上已有的参数', () {
      expect(
        withImageHeight(
          'https://img.example/a.webp?placeholder=L%23abc&t=sig',
          768,
        ),
        'https://img.example/a.webp?placeholder=L%23abc&t=sig&height=768',
      );
    });

    test('已有 height 就地替换，不让同一张图裂成两个缓存键', () {
      expect(
        withImageHeight('https://img.example/a.webp?height=256&t=sig', 1024),
        'https://img.example/a.webp?height=1024&t=sig',
      );
      expect(
        withImageHeight('https://img.example/a.webp?t=sig&height=256', 1024),
        'https://img.example/a.webp?t=sig&height=1024',
      );
    });

    test('不会被前缀相同的参数名骗到', () {
      expect(
        withImageHeight('https://img.example/a.webp?maxheight=256', 512),
        'https://img.example/a.webp?maxheight=256&height=512',
      );
    });

    test('空地址与非法高度原样返回', () {
      expect(withImageHeight('', 512), '');
      expect(
        withImageHeight('https://img.example/a.webp', 0),
        'https://img.example/a.webp',
      );
    });
  });
}
