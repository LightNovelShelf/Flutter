import 'package:flutter/material.dart';

import '../data/api/models.dart';

class BookBadgeDefinition {
  const BookBadgeDefinition({
    required this.id,
    required this.names,
    required this.shortNames,
    required this.color,
    required this.icon,
    required this.label,
    required this.meaning,
  });

  final String id;
  final List<String> names;
  final List<String> shortNames;
  final Color color;
  final IconData icon;
  final String label;
  final String meaning;
}

const List<BookBadgeDefinition> bookBadgeDefinitions = <BookBadgeDefinition>[
  BookBadgeDefinition(
    id: 'recorded',
    names: <String>['录入完成'],
    shortNames: <String>['录入', '录入完成'],
    color: Color(0xFFEC1282),
    icon: Icons.edit_document,
    label: '录入',
    meaning: '人工录入已完成',
  ),
  BookBadgeDefinition(
    id: 'translated',
    names: <String>['翻译完成'],
    shortNames: <String>['翻译', '翻译完成'],
    color: Color(0xFF1976D2),
    icon: Icons.translate,
    label: '翻译',
    meaning: '人工翻译已完成',
  ),
  BookBadgeDefinition(
    id: 'repost',
    names: <String>['转载'],
    shortNames: <String>['转载'],
    color: Color(0xFFF1570E),
    icon: Icons.reply,
    label: '转载',
    meaning: '转载作品',
  ),
  BookBadgeDefinition(
    id: 'original',
    names: <String>['原创'],
    shortNames: <String>['原创'],
    color: Color(0xFF7B1FA2),
    icon: Icons.auto_awesome,
    label: '原创',
    meaning: '原创作品',
  ),
  BookBadgeDefinition(
    id: 'japanese',
    names: <String>['日文原版'],
    shortNames: <String>['日文', '日原', '日文原版'],
    color: Color(0xFFC62828),
    icon: Icons.menu_book,
    label: '日文',
    meaning: '日文原版内容',
  ),
  BookBadgeDefinition(
    id: 'ai',
    names: <String>['AI翻译'],
    shortNames: <String>['AI', 'AI翻译'],
    color: Color(0xFF2EAF5D),
    icon: Icons.smart_toy_outlined,
    label: 'AI',
    meaning: '机器参与生成或翻译',
  ),
  BookBadgeDefinition(
    id: 'recording',
    names: <String>['录入中'],
    shortNames: <String>['录入中'],
    color: Color(0xFF9E9E9E),
    icon: Icons.edit_document,
    label: '录入中',
    meaning: '仍在录入中',
  ),
  BookBadgeDefinition(
    id: 'translating',
    names: <String>['翻译中'],
    shortNames: <String>['翻译中'],
    color: Color(0xFF9E9E9E),
    icon: Icons.translate,
    label: '翻译中',
    meaning: '仍在翻译中',
  ),
];

BookBadgeDefinition? resolveCategoryBadge(BookCategory? category) {
  if (category == null) return null;
  final name = category.name.trim();
  final shortName = category.shortName.trim();
  for (final definition in bookBadgeDefinitions) {
    if (definition.names.contains(name) ||
        definition.shortNames.contains(shortName)) {
      return definition;
    }
  }
  return null;
}

const Color levelBadgeColor = Color(0xFFE0A106);

class LevelBadgeSpec {
  const LevelBadgeSpec({required this.level, required this.interior});

  final int level;
  final bool interior;
}

/// `interiorLevel > 0` 时优先展示组内等级（白底描边），否则展示普通等级。
LevelBadgeSpec? resolveLevelBadge({int? level, int? interiorLevel}) {
  final interior = (interiorLevel ?? 0) > 0;
  final effective = interior ? interiorLevel! : (level ?? 0);
  if (effective <= 0) return null;
  return LevelBadgeSpec(level: effective.clamp(1, 6), interior: interior);
}

/// 徽章图标底座：28×28、圆角 12、图标 14。
class BookBadgeChip extends StatelessWidget {
  const BookBadgeChip({
    super.key,
    required this.background,
    required this.icon,
    required this.iconColor,
    this.border,
    this.trailingLevel,
  });

  final Color background;
  final IconData icon;
  final Color iconColor;
  final BoxBorder? border;
  final int? trailingLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: trailingLevel == null
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 14, color: iconColor),
          if (trailingLevel != null) ...<Widget>[
            const SizedBox(width: 4),
            Text(
              '$trailingLevel',
              style: TextStyle(
                color: iconColor,
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.spec});

  final LevelBadgeSpec spec;

  @override
  Widget build(BuildContext context) => BookBadgeChip(
    background: spec.interior ? Colors.white : levelBadgeColor,
    icon: Icons.hexagon_outlined,
    iconColor: spec.interior ? levelBadgeColor : Colors.white,
    border: spec.interior ? Border.all(color: levelBadgeColor) : null,
    trailingLevel: spec.level,
  );
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.definition});

  final BookBadgeDefinition definition;

  @override
  Widget build(BuildContext context) => BookBadgeChip(
    background: definition.color,
    icon: definition.icon,
    iconColor: Colors.white,
  );
}
