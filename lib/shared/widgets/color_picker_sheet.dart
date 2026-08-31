import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import 'app_sheet.dart';

final RegExp _hexColorPattern = RegExp(r'^[0-9a-fA-F]{6}$');

/// 取色抽屉：支持预设、HSV 滑块、RGB 数值与十六进制输入，确认后返回 `#RRGGBB`。
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
  late HSVColor _hsv;
  late final TextEditingController _hexController;
  late final TextEditingController _redController;
  late final TextEditingController _greenController;
  late final TextEditingController _blueController;

  @override
  void initState() {
    super.initState();
    final color = parseSeedColor(widget.initial);
    _hsv = HSVColor.fromColor(color);
    _hexController = TextEditingController(text: formatHexColor(color));
    _redController = TextEditingController(text: _channel(color.r).toString());
    _greenController = TextEditingController(
      text: _channel(color.g).toString(),
    );
    _blueController = TextEditingController(text: _channel(color.b).toString());
  }

  @override
  void dispose() {
    _hexController.dispose();
    _redController.dispose();
    _greenController.dispose();
    _blueController.dispose();
    super.dispose();
  }

  int _channel(double value) => (value * 255).round();

  int? _parseChannel(TextEditingController controller) {
    final value = int.tryParse(controller.text);
    return value != null && value >= 0 && value <= 255 ? value : null;
  }

  Color? _parseHex(String value) {
    final normalized = value.startsWith('#') ? value.substring(1) : value;
    if (!_hexColorPattern.hasMatch(normalized)) return null;
    return Color(0xFF000000 | int.parse(normalized, radix: 16));
  }

  bool get _hexIsValid => _parseHex(_hexController.text) != null;
  bool get _redIsValid => _parseChannel(_redController) != null;
  bool get _greenIsValid => _parseChannel(_greenController) != null;
  bool get _blueIsValid => _parseChannel(_blueController) != null;
  bool get _allInputsValid =>
      _hexIsValid && _redIsValid && _greenIsValid && _blueIsValid;

  void _syncInputs({TextEditingController? except}) {
    final color = _hsv.toColor();
    if (except != _hexController) {
      _hexController.text = formatHexColor(color);
    }
    if (except != _redController) {
      _redController.text = _channel(color.r).toString();
    }
    if (except != _greenController) {
      _greenController.text = _channel(color.g).toString();
    }
    if (except != _blueController) {
      _blueController.text = _channel(color.b).toString();
    }
  }

  void _setHsv(HSVColor hsv) => setState(() {
    _hsv = hsv;
    _syncInputs();
  });

  /// 灰阶的色相无意义，拖动色相时需要补一个可见的默认饱和度。
  void _setHue(double hue) => _setHsv(
    _hsv
        .withHue(hue)
        .withSaturation(_hsv.saturation == 0 ? 0.1 : _hsv.saturation),
  );

  void _onHexChanged(String value) {
    final color = _parseHex(value);
    setState(() {
      if (color == null) return;
      _hsv = HSVColor.fromColor(color);
      _syncInputs(except: _hexController);
    });
  }

  void _onRgbChanged(TextEditingController source) {
    final red = _parseChannel(_redController);
    final green = _parseChannel(_greenController);
    final blue = _parseChannel(_blueController);
    setState(() {
      if (red == null || green == null || blue == null) return;
      _hsv = HSVColor.fromColor(Color.fromARGB(255, red, green, blue));
      _syncInputs(except: source);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    final hex = formatHexColor(color);
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                          onTap: () => _setHsv(
                            HSVColor.fromColor(parseSeedColor(preset)),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: TextField(
                  key: const ValueKey<String>('color-picker-hex'),
                  controller: _hexController,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    labelText: 'HEX',
                    hintText: '#RRGGBB',
                    errorText: _hexIsValid ? null : '请输入 6 位十六进制颜色',
                  ),
                  onChanged: _onHexChanged,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _RgbField(
                        fieldKey: const ValueKey<String>('color-picker-red'),
                        label: 'R',
                        controller: _redController,
                        valid: _redIsValid,
                        onChanged: (_) => _onRgbChanged(_redController),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RgbField(
                        fieldKey: const ValueKey<String>('color-picker-green'),
                        label: 'G',
                        controller: _greenController,
                        valid: _greenIsValid,
                        onChanged: (_) => _onRgbChanged(_greenController),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RgbField(
                        fieldKey: const ValueKey<String>('color-picker-blue'),
                        label: 'B',
                        controller: _blueController,
                        valid: _blueIsValid,
                        onChanged: (_) => _onRgbChanged(_blueController),
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
                onChanged: (value) => _setHsv(_hsv.withSaturation(value)),
              ),
              _ChannelSlider(
                label: '明度',
                value: _hsv.value,
                max: 1,
                format: (value) => '${(value * 100).round()}%',
                onChanged: (value) => _setHsv(_hsv.withValue(value)),
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
                      onPressed: _allInputsValid
                          ? () => Navigator.of(context).pop(hex)
                          : null,
                      child: const Text('使用此颜色'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RgbField extends StatelessWidget {
  const _RgbField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.valid,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final bool valid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    textAlign: TextAlign.center,
    inputFormatters: <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ],
    decoration: InputDecoration(
      labelText: label,
      errorText: valid ? null : '0–255',
    ),
    onChanged: onChanged,
    onSubmitted: (_) => FocusScope.of(context).unfocus(),
  );
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
