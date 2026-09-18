import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

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
  bool _sosActive = false;
  static const _sosTorchOwner = 'travelease.sos.torch';
  ReceivePort? _sosOwnership;
  bool get _sosOwnsTorch =>
      _sosActive || IsolateNameServer.lookupPortByName(_sosTorchOwner) != null;
  Future<void> _operations = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) async {
      try {
        await operation();
      } catch (_) {
        // Device failures must never interrupt an SOS or notification.
      }
    });
    return _operations;
  }

  Future<void> startSosFlash() {
    if (_sosActive) return _operations;
    _sosActive = true;
    // The background notification isolate uses this same service. A process-
    // local ownership marker prevents its blink routine from switching off SOS.
    final ownership = ReceivePort();
    if (IsolateNameServer.registerPortWithName(
      ownership.sendPort,
      _sosTorchOwner,
    )) {
      _sosOwnership = ownership;
    } else {
      ownership.close();
    }
    return _enqueue(() async {
      if (_sosActive && await TorchLight.isTorchAvailable()) {
        await TorchLight.enableTorch();
      }
    });
  }

  Future<void> stopSosFlash() {
    _sosActive = false;
    return _enqueue(() async {
      try {
        await TorchLight.disableTorch();
      } finally {
        if (!_sosActive && _sosOwnership != null) {
          IsolateNameServer.removePortNameMapping(_sosTorchOwner);
          _sosOwnership!.close();
          _sosOwnership = null;
        }
      }
    });
  }

  /// Flashes the torch twice (~0.28 s on, ~0.22 s off). Fails silently when
  /// the device has no torch, the camera is occupied (e.g. sign camera), or
  /// the category's flash toggle is off.
  Future<void> blinkTwice({bool alert = false}) async {
    if (_busy || _sosOwnsTorch) return;
    final enabled = alert
        ? await NotificationSettings.alertFlashEnabled()
        : await NotificationSettings.generalFlashEnabled();
    if (!enabled || _busy || _sosOwnsTorch) return;
    _busy = true;
    await _enqueue(() async {
      try {
        if (_sosOwnsTorch) return;
        if (!await TorchLight.isTorchAvailable()) return;
        await TorchLight.enableTorch();
        await Future<void>.delayed(const Duration(milliseconds: 280));
        if (_sosOwnsTorch) return;
        await TorchLight.disableTorch();
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (_sosOwnsTorch) return;
        await TorchLight.enableTorch();
        await Future<void>.delayed(const Duration(milliseconds: 280));
        if (_sosOwnsTorch) return;
        await TorchLight.disableTorch();
      } catch (_) {
        // Torch alerts are best-effort; never break the notification flow.
      } finally {
        _busy = false;
      }
    });
  }
}
