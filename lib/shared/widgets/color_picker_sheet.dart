import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'app_sheet.dart';

/// 取色抽屉：预设色块 + 色相/饱和度/明度滑块，确认后返回 `#RRGGBB`。
Future<String?> showColorPickerSheet(
  BuildContext context, {
  required String initial,
  required String title,
  List<String> presets = const <String>[],
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) =>
      _ColorPickerSheet(initial: initial, title: title, presets: presets),
);

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({
    required this.initial,
    required this.title,
    required this.presets,
  });

  final String initial;
  final String title;
  final List<String> presets;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(parseSeedColor(widget.initial));

  /// 灰阶的色相无意义，HSVColor 会把它归到 0，拖色相滑块看不到变化；给个默认饱和度。
  void _setHue(double hue) => setState(
    () => _hsv = _hsv
        .withHue(hue)
        .withSaturation(_hsv.saturation == 0 ? 0.1 : _hsv.saturation),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    final hex = formatHexColor(color);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHeader(icon: Icons.palette_outlined, title: widget.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Container(
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                hex,
                style: TextStyle(
                  color: onAccentColor(color),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          if (widget.presets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final preset in widget.presets)
                    _PresetSwatch(
                      color: parseSeedColor(preset),
                      selected: preset.toUpperCase() == hex,
                      onTap: () => setState(
                        () => _hsv = HSVColor.fromColor(parseSeedColor(preset)),
                      ),
                    ),
                ],
              ),
            ),
          _ChannelSlider(
            label: '色相',
            value: _hsv.hue,
            max: 360,
            format: (value) => value.round().toString(),
            onChanged: _setHue,
          ),
          _ChannelSlider(
            label: '饱和度',
            value: _hsv.saturation,
            max: 1,
            format: (value) => '${(value * 100).round()}%',
            onChanged: (value) =>
                setState(() => _hsv = _hsv.withSaturation(value)),
          ),
          _ChannelSlider(
            label: '明度',
            value: _hsv.value,
            max: 1,
            format: (value) => '${(value * 100).round()}%',
            onChanged: (value) => setState(() => _hsv = _hsv.withValue(value)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(hex),
                  child: const Text('使用此颜色'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 20, color: onAccentColor(color))
            : null,
      ),
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                format(value),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
          Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}
