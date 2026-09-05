import 'package:flutter/foundation.dart';

import '../models/repositories/accessibility_preferences_repository.dart';
import '../services/app_notification_service.dart';

/// Accessibility preferences in two sections: Alert Preferences (important
/// sound alerts) and General Notification Preference (announcements, queue
/// updates and messages together). Each section has push, vibration and
/// flash toggles.
class AccessibilityPreferencesViewModel extends ChangeNotifier {
  AccessibilityPreferencesViewModel({
    AccessibilityPreferencesRepository? repository,
  }) : _repository = repository ?? AccessibilityPreferencesRepository();

  final AccessibilityPreferencesRepository _repository;

  // Alert Preferences.
  bool alertNotification = true;
  bool alertVibration = true;
  bool alertFlash = true;

  // General Notification Preference.
  bool generalNotification = true;
  bool generalVibration = true;
  bool generalFlash = true;

  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final data = await _repository.getCurrentUserPreferences();
      if (data != null) {
        alertNotification = data['alert_notification_enabled'] as bool? ?? true;
        alertVibration = data['alert_vibration_enabled'] as bool? ?? true;
        alertFlash = data['alert_flash_enabled'] as bool? ?? true;
        generalNotification =
            data['general_notification_enabled'] as bool? ?? true;
        generalVibration = data['general_vibration_enabled'] as bool? ?? true;
        generalFlash = data['general_flash_enabled'] as bool? ?? true;
      }
    } catch (_) {
      errorMessage = 'Unable to load accessibility preferences.';
    }
    isLoading = false;
    notifyListeners();
  }

  void update(VoidCallback change) {
    change();
    errorMessage = null;
    notifyListeners();
  }

  /// Toggles persist immediately — leaving the page must not discard them.
  Future<void> setAlertNotification(bool value) =>
      _set(() => alertNotification = value);
  Future<void> setAlertVibration(bool value) =>
      _set(() => alertVibration = value);
  Future<void> setAlertFlash(bool value) => _set(() => alertFlash = value);
  Future<void> setGeneralNotification(bool value) =>
      _set(() => generalNotification = value);
  Future<void> setGeneralVibration(bool value) =>
      _set(() => generalVibration = value);
  Future<void> setGeneralFlash(bool value) => _set(() => generalFlash = value);

  Future<void> _set(VoidCallback change) async {
    update(change);
    await _persist();
  }

  Future<void> _persist() async {
    errorMessage = null;
    try {
      await _repository.saveCurrentUserPreferences({
        'alert_notification_enabled': alertNotification,
        'alert_vibration_enabled': alertVibration,
        'alert_flash_enabled': alertFlash,
        'general_notification_enabled': generalNotification,
        'general_vibration_enabled': generalVibration,
        'general_flash_enabled': generalFlash,
      });
      // Notifications (and the torch flash) follow the saved configuration.
      await AppNotificationService.instance.applyNotificationSettings(
        alertPush: alertNotification,
        alertVibration: alertVibration,
        alertFlash: alertFlash,
        generalPush: generalNotification,
        generalVibration: generalVibration,
        generalFlash: generalFlash,
      );
    } catch (_) {
      errorMessage = 'Unable to save accessibility preferences.';
      notifyListeners();
    }
  }
}
