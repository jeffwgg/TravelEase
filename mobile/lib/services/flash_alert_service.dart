import 'dart:async';

import 'package:torch_light/torch_light.dart';

import 'notification_settings.dart';

/// Blinks the camera torch twice as a visual alert when a notification that
/// matters to a deaf traveller arrives. Honours the flash toggle of the
/// notification category that raised it (notification_settings mirror):
/// [alert] for important sound alerts, otherwise General Notification
/// Preference. Enabled until the profile has been saved once.
class FlashAlertService {
  FlashAlertService._();

  static final instance = FlashAlertService._();

  bool _busy = false;

  /// Flashes the torch twice (~0.28 s on, ~0.22 s off). Fails silently when
  /// the device has no torch, the camera is occupied (e.g. sign camera), or
  /// the category's flash toggle is off.
  Future<void> blinkTwice({bool alert = false}) async {
    if (_busy) return;
    final enabled = alert
        ? await NotificationSettings.alertFlashEnabled()
        : await NotificationSettings.generalFlashEnabled();
    if (!enabled) return;
    _busy = true;
    try {
      if (!await TorchLight.isTorchAvailable()) return;
      await TorchLight.enableTorch();
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await TorchLight.disableTorch();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await TorchLight.enableTorch();
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await TorchLight.disableTorch();
    } catch (_) {
      // Torch alerts are best-effort; never break the notification flow.
    } finally {
      _busy = false;
    }
  }
}
