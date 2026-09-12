import 'dart:async';
import '../models/entities/environment_sound.dart';
import '../models/repositories/environment_sound_repository.dart';
import 'app_notification_service.dart';
import 'environment_sound_detector.dart';
import 'flash_alert_service.dart';

class EnvironmentSoundMonitoringService {
  EnvironmentSoundMonitoringService._();

  static final instance = EnvironmentSoundMonitoringService._();
  final _detector = EnvironmentSoundDetector();
  final _preferences = EnvironmentSoundPreferences();
  StreamSubscription<EnvironmentSoundDetection>? _subscription;

  Future<void> initialize() async {
    _subscription ??= _detector.alerts.listen((detection) {
      // Spoken announcements continue through the dedicated speech-to-text
      // pipeline. Do not send the old generic "announcement detected"
      // notification; the capture service will notify with the transcript.
      if (detection.type == EnvironmentSoundType.speechAnnouncement) return;
      unawaited(
        FlashAlertService.instance
            .blinkTwice(alert: true)
            .then(
              (_) => AppNotificationService.instance.showImportantSound(
                title: '${detection.type.title} detected',
                details:
                    'TravelEase heard ${detection.modelLabel.toLowerCase()} nearby.',
              ),
            ),
      );
    });
    if (!await _preferences.loadEnabled()) return;
    final types = await _preferences.loadTypes();
    if (types.isEmpty) return;
    try {
      await _detector.start(
        enabledTypes: types,
        sensitivity: await _preferences.loadSensitivity(),
      );
    } catch (_) {
      // The settings page reports permission and microphone errors to the user.
    }
  }
}
