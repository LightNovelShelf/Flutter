import '../decode.dart';

class PointLogEntry {
  const PointLogEntry({
    required this.source,
    required this.sourceLabel,
    required this.amount,
    required this.balance,
    required this.referenceId,
    required this.occurredAt,
  });

  final String source;
  final String sourceLabel;
  final int amount;
  final int balance;
  final int? referenceId;
  final DateTime occurredAt;

  static PointLogEntry decode(Object? value) {
    final record = asRecord(value, '流水记录');
    return PointLogEntry(
      source: asString(record['Source']),
      sourceLabel: asString(record['SourceLabel']),
      amount: asInt(record['Amount']),
      balance: asInt(record['Balance']),
      referenceId: asNullableInt(record['RefId']),
      occurredAt: asDate(record['OccurredAt']),
    );
  }
}

class PointLogPage {
  const PointLogPage({
    required this.page,
    required this.totalPages,
    required this.items,
  });

  final int page;
  final int totalPages;
  final List<PointLogEntry> items;

  static PointLogPage decode(Object? value) {
    final record = asRecord(value, '流水响应');
    return PointLogPage(
      page: asInt(record['Page'], 1),
      totalPages: asInt(record['TotalPages'], 0),
      items: asArray(record['Data'], '流水记录').map(PointLogEntry.decode).toList(),
    );
  }
}
