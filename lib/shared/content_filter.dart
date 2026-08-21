import '../data/api/models.dart';
import '../data/settings/app_settings.dart';
import 'book_badges.dart';

/// 排行等接口没有筛选参数，这里按内容设置补一层过滤。
/// 分类名单只此一份，与角标共用 [resolveCategoryBadge] 的匹配规则。
List<BookListItem> applyContentFilter(
  List<BookListItem> items,
  AppSettings settings,
) {
  if (!settings.ignoreJapanese && !settings.ignoreAI) {
    return items;
  }
  return items.where((item) {
    final badgeId = resolveCategoryBadge(item.category)?.id;
    if (badgeId == null) return true;
    if (settings.ignoreJapanese && badgeId == 'japanese') return false;
    if (settings.ignoreAI && badgeId == 'ai') return false;
    return true;
  }).toList();
}
