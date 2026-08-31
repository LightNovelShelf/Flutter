import 'package:flutter/material.dart';

/// 分组设置列表：外层 padding 16/8/16/112，分组间距 20。
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ListView.separated(
    controller: controller,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
    itemCount: children.length,
    separatorBuilder: (_, _) => const SizedBox(height: 20),
    itemBuilder: (_, index) => children[index],
  );
}

/// 一个设置分组：标题 + 圆角 22 的行容器。
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              title!,
              style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        Material(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (
                var index = 0;
                index < children.length;
                index += 1
              ) ...<Widget>[
                if (index > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colors.outlineVariant,
                  ),
                children[index],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: icon == null
          ? null
          : SizedBox(
              width: 28,
              height: 28,
              child: Icon(icon, size: 22, color: colors.primary),
            ),
      title: Text(title),
      subtitle: description == null ? null : Text(description!),
      trailing: trailing,
    );
  }
}

class SettingsNavigationRow extends StatelessWidget {
  const SettingsNavigationRow({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final String? value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsRow(
      title: title,
      description: description,
      icon: icon,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (value != null)
            Text(value!, style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.title,
    this.description,
    this.icon,
    required this.value,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsRow(
      title: title,
      description: description,
      icon: icon,
      enabled: enabled,
      onTap: onTap,
      trailing: Text(value, style: TextStyle(color: colors.onSurfaceVariant)),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    this.description,
    this.icon,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title: title,
    description: description,
    icon: icon,
    enabled: enabled,
    onTap: enabled ? () => onChanged(!value) : null,
    trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
  );
}

class SettingsPickerRow<T> extends StatelessWidget {
  const SettingsPickerRow({
    super.key,
    required this.title,
    this.description,
    this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final T value;
  final List<(T value, String label)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = options
        .firstWhere((option) => option.$1 == value, orElse: () => options.first)
        .$2;
    return SettingsRow(
      title: title,
      description: description,
      icon: icon,
      enabled: enabled,
      onTap: enabled
          ? () async {
              final selected = await showModalBottomSheet<T>(
                context: context,
                builder: (context) => SafeArea(
                  child: RadioGroup<T>(
                    groupValue: value,
                    onChanged: (next) => Navigator.of(context).pop(next),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        for (final option in options)
                          RadioListTile<T>(
                            value: option.$1,
                            title: Text(option.$2),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
              if (selected != null) onChanged(selected);
            }
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 20, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// 滑块行：数值格式化后拼进副标题（`说明 · 值`）。
class SettingsSliderRow extends StatelessWidget {
  const SettingsSliderRow({
    super.key,
    required this.title,
    required this.description,
    this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String title;
  final String description;
  final IconData? icon;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(icon, size: 22, color: colors.primary),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      '$description · ${format(value)}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
