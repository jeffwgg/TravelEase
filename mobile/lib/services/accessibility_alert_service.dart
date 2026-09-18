import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notification_settings.dart';
import 'flash_alert_service.dart';
import '../core/hardware_services.dart';

class AccessibilityAlertService {
  static const _channel = MethodChannel('travelease/accessibility_alerts');
  int _sosOperation = 0;
  bool _sosActive = false;

  Future<void> startSosAlerts() async {
    if (_sosActive) return;
    _sosActive = true;
    await Future.wait([
      vibrateForSos(),
      FlashAlertService.instance.startSosFlash(),
      HardwareServices().startSosAudio(),
    ]);
  }

  Future<void> stopSosAlerts() async {
    if (!_sosActive) return;
    _sosActive = false;
    await Future.wait([
      stopSosVibration(),
      FlashAlertService.instance.stopSosFlash(),
      HardwareServices().stopSosAudio(),
    ]);
  }

  Future<void> testVibration(String strength) async {
    await _channel.invokeMethod<void>('vibrate', {'strength': strength});
  }

  /// Starts the SOS waveform using the locally mirrored accessibility profile.
  /// It is deliberately best-effort so hardware/channel failure cannot block
  /// the emergency flow.
  Future<void> vibrateForSos() async {
    final operation = ++_sosOperation;
    try {
      if (!await NotificationSettings.alertVibrationEnabled()) return;
      if (operation != _sosOperation) return;
      final strength = await NotificationSettings.vibrationStrength();
      if (operation != _sosOperation) return;
      await _channel.invokeMethod<void>('vibrate', {
        'strength': strength,
        'sosPattern': true,
      });
    } catch (error) {
      debugPrint('[SOS] Vibration unavailable: $error');
    }
  }

  Future<void> stopSosVibration() async {
    _sosOperation++;
    try {
      await _channel.invokeMethod<void>('stopVibration');
    } catch (error) {
      debugPrint('[SOS] Unable to stop vibration: $error');
    }
  }

  Future<void> testFlash() async {
    await _channel.invokeMethod<void>('flash');
  }
}
