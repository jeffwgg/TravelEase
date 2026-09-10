import 'package:flutter/services.dart';

class AccessibilityAlertService {
  static const _channel = MethodChannel('travelease/accessibility_alerts');

  Future<void> testVibration(String strength) async {
    await _channel.invokeMethod<void>('vibrate', {'strength': strength});
  }

  Future<void> testFlash() async {
    await _channel.invokeMethod<void>('flash');
  }
}
