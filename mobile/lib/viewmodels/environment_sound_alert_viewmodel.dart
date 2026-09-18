import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/entities/environment_sound.dart';
import '../models/repositories/environment_sound_repository.dart';
import '../services/app_notification_service.dart';
import '../services/environment_sound_detector.dart';
import '../services/public_announcement_capture_service.dart';

enum EnvironmentSoundMessageType { error, success, information }

/// State and use-cases for Module 2 environment-sound monitoring.
class EnvironmentSoundAlertViewModel extends ChangeNotifier {
  EnvironmentSoundAlertViewModel({
    EnvironmentSoundDetector? detector,
    EnvironmentSoundPreferences? preferences,
  }) : _detector = detector ?? EnvironmentSoundDetector(),
       _preferences = preferences ?? EnvironmentSoundPreferences();

  final EnvironmentSoundDetector _detector;
  final EnvironmentSoundPreferences _preferences;
  final StreamController<EnvironmentSoundDetection> _displayAlerts =
      StreamController.broadcast();

  final Set<EnvironmentSoundType> enabledTypes = {};
  final List<EnvironmentSoundDetection> history = [];
  SoundSensitivity sensitivity = SoundSensitivity.balanced;
  SoundDetectionSnapshot snapshot = SoundDetectionSnapshot.idle;
  bool enabled = false;
  bool loading = true;
  bool changingMonitoring = false;
  String? message;
  EnvironmentSoundMessageType messageType =
      EnvironmentSoundMessageType.information;

  StreamSubscription<SoundDetectionSnapshot>? _snapshotSubscription;
  StreamSubscription<EnvironmentSoundDetection>? _alertSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _initialized = false;
  bool _disposed = false;

  /// Non-persistent presentation effects; the view owns its dialog and haptic
  /// rendering while this model persists and publishes the detection.
  Stream<EnvironmentSoundDetection> get displayAlerts => _displayAlerts.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _snapshotSubscription = _detector.snapshots.listen((nextSnapshot) {
      if (_disposed) return;
      snapshot = nextSnapshot;
      _notify();
    });
    _alertSubscription = _detector.alerts.listen(_handleDetection);
    _errorSubscription = _detector.errors.listen(_handleDetectorError);
    await loadPreferences();
  }

  void _handleDetectorError(String errorMessage) {
    if (_disposed) return;
    enabled = false;
    changingMonitoring = false;
    message = errorMessage;
    messageType = EnvironmentSoundMessageType.error;
    _notify();
  }

  Future<void> loadPreferences() async {
    final values = await Future.wait([
      _preferences.loadEnabled(),
      _preferences.loadTypes(),
      _preferences.loadSensitivity(),
      _preferences.loadHistory(),
    ]);
    if (_disposed) return;
    final savedHistory = values[3] as List<EnvironmentSoundDetection>;
    final alertHistory = savedHistory
        .where(
          (detection) =>
              detection.type != EnvironmentSoundType.speechAnnouncement,
        )
        .toList();
    final shouldStart = values[0] as bool;
    enabledTypes
      ..clear()
      ..addAll(values[1] as Set<EnvironmentSoundType>);
    sensitivity = values[2] as SoundSensitivity;
    history
      ..clear()
      ..addAll(alertHistory);
    loading = false;
    _notify();

    if (alertHistory.length != savedHistory.length) {
      unawaited(_preferences.saveHistory(alertHistory));
    }
    if (shouldStart) await setMonitoring(true);
  }

  Future<void> setMonitoring(bool shouldEnable) async {
    if (changingMonitoring) return;
    if (shouldEnable && enabledTypes.isEmpty) {
      message = 'Select at least one sound to detect.';
      messageType = EnvironmentSoundMessageType.information;
      _notify();
      return;
    }
    changingMonitoring = true;
    _notify();
    try {
      if (shouldEnable) {
        await AppNotificationService.instance.requestPermission();
        await _detector.start(
          enabledTypes: enabledTypes,
          sensitivity: sensitivity,
        );
      } else {
        // Persist the off state before awaiting microphone teardown. An
        // in-flight recogniser checks this preference before publishing.
        enabled = false;
        await saveSettings();
        await PublicAnnouncementCaptureService.instance.cancelPendingCapture();
        await _detector.stop();
      }
      if (_disposed) return;
      enabled = shouldEnable;
      message = shouldEnable
          ? 'Important sound monitoring is active.'
          : 'Important sound monitoring is off.';
      messageType = shouldEnable
          ? EnvironmentSoundMessageType.success
          : EnvironmentSoundMessageType.information;
      _notify();
      await saveSettings();
    } on EnvironmentSoundException catch (exception) {
      if (_disposed) return;
      enabled = false;
      message =
          '${exception.message} Allow microphone access in device settings, then try again.';
      messageType = EnvironmentSoundMessageType.error;
    } catch (exception) {
      if (_disposed) return;
      enabled = false;
      message = 'Unable to start sound detection: $exception';
      messageType = EnvironmentSoundMessageType.error;
    } finally {
      if (!_disposed) {
        changingMonitoring = false;
        _notify();
      }
    }
  }

  Future<void> saveSettings() => _preferences.saveSettings(
    enabled: enabled,
    types: enabledTypes,
    sensitivity: sensitivity,
  );

  void setSoundEnabled(EnvironmentSoundType type, bool isEnabled) {
    if (isEnabled) {
      enabledTypes.add(type);
    } else {
      enabledTypes.remove(type);
    }
    _detector.updateConfiguration(
      enabledTypes: enabledTypes,
      sensitivity: sensitivity,
    );
    if (type == EnvironmentSoundType.speechAnnouncement && !isEnabled) {
      unawaited(
        PublicAnnouncementCaptureService.instance.cancelPendingCapture(),
      );
    }
    unawaited(saveSettings());
    _notify();
  }

  void setSensitivity(SoundSensitivity? nextSensitivity) {
    if (nextSensitivity == null || nextSensitivity == sensitivity) return;
    sensitivity = nextSensitivity;
    _detector.updateConfiguration(
      enabledTypes: enabledTypes,
      sensitivity: sensitivity,
    );
    unawaited(saveSettings());
    _notify();
  }

  Future<void> _handleDetection(EnvironmentSoundDetection detection) async {
    if (_disposed ||
        detection.type == EnvironmentSoundType.speechAnnouncement) {
      return;
    }
    // Announcement capture owns speech events. It appears in Announcements
    // and Notifications, never in the generic alert history or modal alerts.
    history.insert(0, detection);
    _notify();
    await _preferences.saveHistory(history);
    if (!_disposed) _displayAlerts.add(detection);
  }

  Future<void> clearHistory() async {
    await _preferences.clearHistory();
    if (_disposed) return;
    history.clear();
    _notify();
  }

  void dismissMessage() {
    if (message == null) return;
    message = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_snapshotSubscription?.cancel());
    unawaited(_alertSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_displayAlerts.close());
    super.dispose();
  }
}
