import 'dart:async';

import 'package:torch_light/torch_light.dart';

/// Blinks the camera torch twice as a visual alert when a notification that
/// matters to a deaf traveller arrives. Configuration is hardcoded enabled
/// for now; a settings section will control it later.
class FlashAlertService {
  FlashAlertService._();

  static final instance = FlashAlertService._();

  bool _busy = false;

  /// Flashes the torch twice (~0.28 s on, ~0.22 s off). Fails silently when
  /// the device has no torch or the camera is occupied (e.g. sign camera).
  Future<void> blinkTwice() async {
    if (_busy) return;
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
