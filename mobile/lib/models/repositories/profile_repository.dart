import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class ProfileRepository {
  ProfileRepository({SupabaseClient? client})
      : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final response = await _client
        .from('user_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<bool> isCurrentUserProfileComplete() async {
    final profile = await getCurrentUserProfile();
    return profile?['profile_completed'] == true;
  }

  Future<void> saveTravellerProfile({
    required String fullName,
    required String nationality,
    required String primaryLanguage,
    String? secondaryLanguage,
    required String preferredCommunication,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No authenticated user is available.');
    }

    await _client.from('user_profiles').upsert({
      'id': user.id,
      'full_name': fullName,
      'nationality': nationality,
      'primary_language': primaryLanguage,
      'secondary_language': secondaryLanguage,
      'preferred_communication': preferredCommunication,
      'user_type': 'traveller',
      'profile_completed': true,
    });
  }

  Future<void> updateCurrentUserProfile({
    required String fullName,
    required String nationality,
    required String preferredCommunication,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No authenticated user is available.');
    }

    await _client.from('user_profiles').update({
      'full_name': fullName,
      'nationality': nationality,
      'preferred_communication': preferredCommunication,
      'user_type': 'traveller',
    }).eq('id', user.id);

    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );
  }
}
