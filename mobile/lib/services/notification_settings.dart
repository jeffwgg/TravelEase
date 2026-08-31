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
  static const flashKey = 'notification_flash_enabled';
  static const _channelsVibrationKey = 'notification_channels_vibration';

  static Future<bool> vibrationEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(vibrationKey) ?? true;
  }

  static Future<bool> flashEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(flashKey) ?? true;
  }

  static Future<void> store({
    required bool vibration,
    required bool flash,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(vibrationKey, vibration);
    await preferences.setBool(flashKey, flash);
  }

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
