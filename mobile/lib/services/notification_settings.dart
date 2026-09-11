import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local mirror of the profile accessibility configuration that governs
/// notification behaviour: [vibrationKey] mirrors the profile "Vibration
/// Alerts" toggle, [flashKey] the "Flash Alerts" toggle. The profile screen
/// writes the mirror whenever preferences are saved; notification services
/// read it — including the background isolate, which has no Supabase
/// session. Until the profile has been saved once the defaults keep the
/// previous always-on behaviour.
class NotificationSettings {
  static const vibrationKey = 'notification_vibration_enabled';
  static const vibrationStrengthKey = 'notification_vibration_strength';
  static const flashKey = 'notification_flash_enabled';
  static const _channelsVibrationKey = 'notification_channels_vibration';
  static const _accessibilityPreferencesKey = 'accessibility_preferences';

  static Future<bool> vibrationEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(vibrationKey) ?? true;
  }

  static Future<bool> flashEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(flashKey) ?? true;
  }

  static Future<String> vibrationStrength() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(vibrationStrengthKey);
    if (_validStrength(stored)) return stored!;

    // Existing installations already cache the complete accessibility profile
    // under this key. Read it as a migration fallback until the next save.
    final profileJson = preferences.getString(_accessibilityPreferencesKey);
    if (profileJson != null) {
      try {
        final profile = jsonDecode(profileJson) as Map<String, dynamic>;
        final profileStrength = profile['vibration_strength'] as String?;
        if (_validStrength(profileStrength)) return profileStrength!;
      } catch (_) {
        // A damaged cache falls back safely to the established default.
      }
    }
    return 'medium';
  }

  static Future<void> store({
    required bool vibration,
    required String vibrationStrength,
    required bool flash,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(vibrationKey, vibration);
    await preferences.setString(
      vibrationStrengthKey,
      _validStrength(vibrationStrength) ? vibrationStrength : 'medium',
    );
    await preferences.setBool(flashKey, flash);
  }

  static bool _validStrength(String? value) =>
      const {'light', 'medium', 'strong'}.contains(value);

  /// Remembers which vibration configuration the Android notification
  /// channels were last created with, so they are only recreated when the
  /// setting actually changes.
  static Future<bool?> channelsVibration() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_channelsVibrationKey);
  }

  static Future<void> setChannelsVibration(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_channelsVibrationKey, value);
  }
}
