import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _batteryChannel = MethodChannel(
  'app.lightnovel.shelf/battery',
);

@immutable
class BatteryStatus {
  const BatteryStatus({required this.level, required this.charging});

  final int level;
  final bool charging;
}

Future<BatteryStatus?> readBatteryStatus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final raw = await _batteryChannel.invokeMapMethod<String, Object?>(
      'getBattery',
    );
    final level = raw?['level'];
    if (level is! int || level < 0) return null;
    return BatteryStatus(
      level: level.clamp(0, 100).toInt(),
      charging: raw?['charging'] == true,
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
