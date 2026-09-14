import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../entities/environment_sound.dart';

class EnvironmentSoundPreferences {
  static const _enabledKey = 'environment_sound_enabled';
  static const _typesKey = 'environment_sound_types';
  static const _sensitivityKey = 'environment_sound_sensitivity';
  static const _historyKey = 'environment_sound_history';

  Future<bool> loadEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  Future<Set<EnvironmentSoundType>> loadTypes() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList(_typesKey);
    final types = saved == null
        ? EnvironmentSoundType.values.toSet()
        : EnvironmentSoundType.values
              .where((type) => saved.contains(type.name))
              .toSet();
    return types;
  }

  Future<SoundSensitivity> loadSensitivity() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_sensitivityKey);
    return SoundSensitivity.values.firstWhere(
      (value) => value.name == saved,
      orElse: () => SoundSensitivity.balanced,
    );
  }

  Future<List<EnvironmentSoundDetection>> loadHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_historyKey) ?? const [];
    return values
        .map(
          (value) => EnvironmentSoundDetection.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> saveSettings({
    required bool enabled,
    required Set<EnvironmentSoundType> types,
    required SoundSensitivity sensitivity,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
    await preferences.setStringList(
      _typesKey,
      types.map((type) => type.name).toList(),
    );
    await preferences.setString(_sensitivityKey, sensitivity.name);
  }

  Future<void> saveHistory(List<EnvironmentSoundDetection> history) async {
    final preferences = await SharedPreferences.getInstance();
    final limited = history
        .take(20)
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await preferences.setStringList(_historyKey, limited);
  }

  Future<void> clearHistory() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_historyKey);
  }
}
