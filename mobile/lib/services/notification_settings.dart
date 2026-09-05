import 'package:shared_preferences/shared_preferences.dart';

/// Local mirror of the profile notification configuration. The profile
/// screen writes it whenever preferences are saved; notification services
/// read it — including the background isolate, which has no Supabase
/// session. Until the profile has been saved once the defaults keep the
/// previous always-on behaviour.
///
/// There are two notification categories, each with its own push, vibration
/// and flash controls:
/// - **Alerts** — important sound / emergency alerts raised while monitoring
///   the environment.
/// - **General notifications** — everything else: official and captured
///   announcements, queue updates and staff messages, controlled together.
class NotificationSettings {
  static const alertPushKey = 'alert_notification_enabled';
  static const alertVibrationKey = 'alert_vibration_enabled';
  static const alertFlashKey = 'alert_flash_enabled';
  static const generalPushKey = 'general_notification_enabled';
  static const generalVibrationKey = 'general_vibration_enabled';
  static const generalFlashKey = 'general_flash_enabled';
  static const _channelsGenerationKey = 'notification_channels_generation';

  static Future<bool> alertPushEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(alertPushKey) ?? true;
  }

  static Future<bool> alertVibrationEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(alertVibrationKey) ?? true;
  }

  static Future<bool> alertFlashEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(alertFlashKey) ?? true;
  }

  static Future<bool> generalPushEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(generalPushKey) ?? true;
  }

  static Future<bool> generalVibrationEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(generalVibrationKey) ?? true;
  }

  static Future<bool> generalFlashEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(generalFlashKey) ?? true;
  }

  static Future<void> store({
    required bool alertPush,
    required bool alertVibration,
    required bool alertFlash,
    required bool generalPush,
    required bool generalVibration,
    required bool generalFlash,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(alertPushKey, alertPush);
    await preferences.setBool(alertVibrationKey, alertVibration);
    await preferences.setBool(alertFlashKey, alertFlash);
    await preferences.setBool(generalPushKey, generalPush);
    await preferences.setBool(generalVibrationKey, generalVibration);
    await preferences.setBool(generalFlashKey, generalFlash);
  }

  /// Generation counter for the Android notification channel ids. Android
  /// remembers deleted channel ids and keeps their old settings, so a
  /// vibration change must create channels under a NEW id generation
  /// instead of recreating the same ids.
  static Future<int> channelsGeneration() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_channelsGenerationKey) ?? 0;
  }

  static Future<void> setChannelsGeneration(int value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_channelsGenerationKey, value);
  }
}
