import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';

void main() {
  test('decodes point log page and entries', () {
    final page = PointLogPage.decode(<String, Object?>{
      'Page': 2,
      'TotalPages': 4,
      'Data': <Object?>[
        <String, Object?>{
          'Source': 'SignIn',
          'SourceLabel': '签到',
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
    expect(page.items.single.sourceLabel, '签到');
    expect(page.items.single.amount, 12);
    expect(page.items.single.balance, 120);
    expect(page.items.single.referenceId, isNull);
    expect(
      page.items.single.occurredAt.toUtc(),
      DateTime.utc(2026, 8, 30, 8, 30),
    );
  });
}
