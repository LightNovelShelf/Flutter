import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/platform/battery_status.dart';

class ReaderFrameInfo extends StatelessWidget {
  const ReaderFrameInfo({
    super.key,
    required this.title,
    required this.foregroundColor,
    required this.infoVisible,
    this.trailing,
  });

  static const double edgeGap = 12;
  static const double rowExtent = 24;
  static const double bodyGap = 8;
  static const double footerExtent = edgeGap + rowExtent + bodyGap;

  static double headerTopOf(EdgeInsets padding) =>
      math.max(padding.top, padding.bottom + edgeGap);

  static EdgeInsets bandsOf(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.only(
      top: headerTopOf(padding) + rowExtent + bodyGap,
      bottom: padding.bottom + footerExtent,
    );
  }

  final String title;
  final Color foregroundColor;
  final bool infoVisible;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final bottom = bandsOf(context).bottom;
    final style = TextStyle(
      color: foregroundColor.withValues(alpha: 0.6),
      fontSize: 12,
      height: 16 / 12,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final sides = EdgeInsets.only(
      left: 16 + padding.left,
      right: 16 + padding.right,
    );
    return Stack(
      children: <Widget>[
        Positioned(
          top: headerTopOf(padding),
          left: 0,
          right: 0,
          height: rowExtent,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: infoVisible ? 1 : 0,
              child: Padding(
                padding: sides,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      key: const ValueKey<String>('reader-frame-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottom,
          child: Padding(
            padding: sides.copyWith(bottom: padding.bottom + edgeGap),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                children: <Widget>[
                  IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: infoVisible ? 1 : 0,
                      child: ReaderClockBattery(style: style),
                    ),
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReaderClockBattery extends StatefulWidget {
  const ReaderClockBattery({super.key, required this.style});

  final TextStyle style;

  @override
  State<ReaderClockBattery> createState() => _ReaderClockBatteryState();
}

class _ReaderClockBatteryState extends State<ReaderClockBattery>
    with WidgetsBindingObserver {
  DateTime _now = DateTime.now();
  BatteryStatus? _battery;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _now = DateTime.now());
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    unawaited(_readBattery());
    final now = DateTime.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _timer = Timer(next.difference(now), _refresh);
  }

  Future<void> _readBattery() async {
    final battery = await readBatteryStatus();
    if (!mounted) return;
    setState(() => _battery = battery);
  }

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_now),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final battery = _battery;
    final color = widget.style.color ?? const Color(0x99000000);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (battery != null) ...<Widget>[
          CustomPaint(
            size: const Size(20, 10),
            painter: _BatteryPainter(
              level: battery.level,
              charging: battery.charging,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text('${battery.level}%', style: widget.style),
          const SizedBox(width: 10),
        ],
        Text(
          time,
          key: const ValueKey<String>('reader-clock'),
          style: widget.style,
        ),
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({
    required this.level,
    required this.charging,
    required this.color,
  });

  final int level;
  final bool charging;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const nub = 2.0;
    final body = Rect.fromLTWH(0.5, 0.5, size.width - nub - 1, size.height - 1);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(2)),
      outline,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width - nub,
        size.height * 0.3,
        nub,
        size.height * 0.4,
      ),
      Paint()..color = color,
    );
    final inner = body.deflate(1.5);
    canvas.drawRect(
      Rect.fromLTWH(
        inner.left,
        inner.top,
        inner.width * level / 100,
        inner.height,
      ),
      Paint()..color = charging ? Colors.green.shade600 : color,
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.charging != charging ||
      oldDelegate.color != color;
}
