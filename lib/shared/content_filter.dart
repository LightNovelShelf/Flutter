import '../data/api/models.dart';
import '../data/settings/app_settings.dart';

const List<String> _japaneseShortNames = <String>['日文', '日原', '日文原版'];
const List<String> _aiShortNames = <String>['AI', 'AI翻译'];

/// 排行等接口没有筛选参数，这里按内容设置补一层过滤。
List<BookListItem> applyContentFilter(
  List<BookListItem> items,
  AppSettings settings,
) {
  if (!settings.ignoreJapanese && !settings.ignoreAI) {
    return items;
  }
  return items.where((item) {
    final category = item.category;
    if (category == null) return true;
    final name = category.name.trim();
    final shortName = category.shortName.trim();
    if (settings.ignoreJapanese &&
        (name == '日文原版' || _japaneseShortNames.contains(shortName))) {
      return false;
    }
    if (settings.ignoreAI &&
        (name == 'AI翻译' || _aiShortNames.contains(shortName))) {
      return false;
    }
    return true;
  }).toList();
}
