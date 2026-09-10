import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class AccessibilityPreferencesRepository {
  AccessibilityPreferencesRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;
  static const _localKey = 'accessibility_preferences';

  Future<Map<String, dynamic>?> getCurrentUserPreferences() async {
    final localJson = (await SharedPreferences.getInstance()).getString(
      _localKey,
    );
    final local = localJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(localJson) as Map);
    final user = _client.auth.currentUser;
    if (user == null) return local.isEmpty ? null : local;
    try {
      final response = await _client
          .from('accessibility_preferences')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (response == null) return local.isEmpty ? null : local;
      return {...local, ...Map<String, dynamic>.from(response)};
    } catch (_) {
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<void> saveCurrentUserPreferences(
    Map<String, dynamic> preferences,
  ) async {
    final local = await SharedPreferences.getInstance();
    await local.setString(_localKey, jsonEncode(preferences));
    final user = _client.auth.currentUser;
    if (user == null) return;
    final remotePreferences = Map<String, dynamic>.from(preferences);
    try {
      await _client.from('accessibility_preferences').upsert({
        'user_id': user.id,
        ...remotePreferences,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // The local copy is authoritative for on-device accessibility behavior.
      // Cloud sync can recover on the next save when connectivity returns.
    }
  }
}
