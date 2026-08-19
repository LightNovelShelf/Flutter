import 'package:intl/intl.dart';

final NumberFormat _decimalFormat = NumberFormat.decimalPattern('zh_CN');
final DateFormat _mediumDate = DateFormat('yyyy年M月d日', 'zh_CN');
final DateFormat _shortDate = DateFormat('yyyy-MM-dd', 'zh_CN');
final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm', 'zh_CN');

String formatCount(int value) => _decimalFormat.format(value);

String formatMediumDate(DateTime? value) =>
    value == null ? '暂无' : _mediumDate.format(value);

String formatShortDate(DateTime? value) =>
    value == null ? '' : _shortDate.format(value);

String formatDateTime(DateTime? value) =>
    value == null ? '' : _dateTime.format(value);

/// 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前，超过 30 天回落到日期。
String formatRelativeTime(DateTime? value) {
  if (value == null) return '';
  final delta = DateTime.now().difference(value);
  if (delta.isNegative) return '刚刚';
  if (delta.inMinutes < 1) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
  if (delta.inHours < 24) return '${delta.inHours} 小时前';
  if (delta.inDays < 30) return '${delta.inDays} 天前';
  return _shortDate.format(value);
}

/// 去掉章节标题里重复的书名/卷名前缀，只保留编号或名称。
final RegExp _chapterNoisePattern =
    RegExp(r'^\s*(?:第?\s*[0-9一二三四五六七八九十百]+\s*[章话節节卷]\s*)');

String cleanChapterTitle(String title) {
  final trimmed = title.trim();
  final stripped = trimmed.replaceFirst(_chapterNoisePattern, '').trim();
  return stripped.isEmpty ? trimmed : stripped;
}
