import 'package:flutter/material.dart';

/// 精选星标的固定琥珀色，不随主题变化。
const Color communityFeaturedColor = Color(0xFFF59E0B);
const Color _lockedBackground = Color(0xFFFEF3C7);
const Color _lockedForeground = Color(0xFFB45309);

/// 等宽数字，避免计数变化时行内文字抖动。
const TextStyle communityTabular = TextStyle(
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

/// 社区通用卡片，无阴影，只有一条细边框。
class CommunityCard extends StatelessWidget {
  const CommunityCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.background,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? colors.outlineVariant, width: 0.5),
    );
    return Material(
      color: background ?? colors.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class CommunityFilterChip extends StatelessWidget {
  const CommunityFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? colors.onPrimaryContainer : colors.primary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityFilterCaption extends StatelessWidget {
  const CommunityFilterCaption({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 静态标签胶囊，版面用强调色，子分类和状态用中性色。
/// `dense` 收紧 padding，用于回复行内的徽章。
class CommunityTagPill extends StatelessWidget {
  const CommunityTagPill({
    super.key,
    required this.label,
    this.tone = CommunityTagTone.accent,
    this.dense = false,
  });

  final String label;
  final CommunityTagTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (
      Color background,
      Color foreground,
      FontWeight weight,
    ) = switch (tone) {
      CommunityTagTone.accent => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        FontWeight.w700,
      ),
      CommunityTagTone.neutral => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        FontWeight.w600,
      ),
      CommunityTagTone.locked => (
        _lockedBackground,
        _lockedForeground,
        FontWeight.w700,
      ),
    };
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: weight, color: foreground),
      ),
    );
  }
}

enum CommunityTagTone { accent, neutral, locked }

/// 卡片形态的空状态与错误状态，用于列表内部。
class CommunityStateCard extends StatelessWidget {
  const CommunityStateCard({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.forum_outlined,
    this.isError = false,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isError;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CommunityCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              isError ? Icons.error_outline : icon,
              size: 22,
              color: isError ? colors.error : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}
