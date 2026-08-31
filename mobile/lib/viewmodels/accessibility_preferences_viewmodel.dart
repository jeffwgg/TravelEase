import 'package:flutter/foundation.dart';

import '../models/repositories/accessibility_preferences_repository.dart';
import '../services/app_notification_service.dart';

class AccessibilityPreferencesViewModel extends ChangeNotifier {
  AccessibilityPreferencesViewModel({
    AccessibilityPreferencesRepository? repository,
  }) : _repository = repository ?? AccessibilityPreferencesRepository();

  final AccessibilityPreferencesRepository _repository;

  double captionSize = 16;
  bool highContrast = false;
  bool fullScreenAlerts = true;
  bool vibration = true;
  String vibrationStrength = 'medium';
  bool flashAlerts = false;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final data = await _repository.getCurrentUserPreferences();
      if (data != null) {
        captionSize = ((data['caption_size'] as num?)?.toDouble() ?? 16)
            .clamp(12, 28)
            .toDouble();
        highContrast = data['high_contrast'] as bool? ?? false;
        fullScreenAlerts = data['full_screen_alerts'] as bool? ?? true;
        vibration = data['vibration'] as bool? ?? true;
        final strength = data['vibration_strength'] as String?;
        vibrationStrength =
            const {'light', 'medium', 'strong'}.contains(strength)
            ? strength!
            : 'medium';
        flashAlerts = data['flash_alerts'] as bool? ?? false;
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

  Future<bool> save() async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _repository.saveCurrentUserPreferences({
        'caption_size': captionSize,
        'high_contrast': highContrast,
        'full_screen_alerts': fullScreenAlerts,
        'vibration': vibration,
        'vibration_strength': vibrationStrength,
        'flash_alerts': flashAlerts,
      });
      // Notifications (and the torch flash) follow the saved configuration.
      await AppNotificationService.instance.applyNotificationSettings(
        vibration: vibration,
        flash: flashAlerts,
      );
      isSaving = false;
      notifyListeners();
      return true;
    } catch (_) {
      isSaving = false;
      errorMessage = 'Unable to save accessibility preferences.';
      notifyListeners();
      return false;
    }
  }
}
