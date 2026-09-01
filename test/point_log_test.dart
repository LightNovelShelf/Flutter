import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/features/settings/point_log_sheet.dart';

void main() {
  test('decodes point log page and entries', () {
    final page = PointLogPage.decode(<String, Object?>{
      'Page': 2,
      'TotalPages': 4,
      'Data': <Object?>[
        <String, Object?>{
          'Source': 'SignIn',
          'Amount': 12,
          'Balance': 120,
          'RefId': null,
          'OccurredAt': '2026-08-30T08:30:00Z',
        },
      ],
    });

    expect(page.page, 2);
    expect(page.totalPages, 4);
    expect(page.items, hasLength(1));
    expect(page.items.single.source, 'SignIn');
    expect(page.items.single.amount, 12);
    expect(page.items.single.balance, 120);
    expect(page.items.single.referenceId, isNull);
    expect(
      page.items.single.occurredAt.toUtc(),
      DateTime.utc(2026, 8, 30, 8, 30),
    );
  });

  test('labels rewards, clawbacks, spending, and unknown sources', () {
    expect(pointLogSourceLabel('PublishNovel', 10), '发布小说');
    expect(pointLogSourceLabel('PublishNovel', -10), '发布小说回收');
    expect(pointLogSourceLabel('ShopPurchase', -10), '商店购买');
    expect(pointLogSourceLabel('ComicRead', -5), '漫画阅读');
    expect(pointLogSourceLabel('FutureSource', 10), 'FutureSource');
  });
}
