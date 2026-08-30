import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class ProfileRepository {
  ProfileRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;
  static const avatarBucket = 'profile-images';

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
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No authenticated user is available.');
    }

    await _client
        .from('user_profiles')
        .update({
          'full_name': fullName,
          'nationality': nationality,
          'user_type': 'traveller',
        })
        .eq('id', user.id);

    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _client.auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthException('No authenticated user is available.');
    }
    await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No authenticated user is available.');
    }
    final path = '${user.id}/avatar';
    debugPrint(
      '[AvatarUpload] Starting upload: bucket=$avatarBucket path=$path '
      'bytes=${bytes.length} contentType=$contentType upsert=true',
    );
    try {
      final uploadedPath = await _client.storage
          .from(avatarBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      debugPrint('[AvatarUpload] Storage upload succeeded: $uploadedPath');

      final publicUrl = _client.storage.from(avatarBucket).getPublicUrl(path);
      debugPrint('[AvatarUpload] Public URL generated: $publicUrl');
      final versionedUrl =
          '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await _client
          .from('user_profiles')
          .update({'avatar_url': versionedUrl})
          .eq('id', user.id);
      debugPrint('[AvatarUpload] user_profiles.avatar_url updated');
      await _client.auth.updateUser(
        UserAttributes(data: {'avatar_url': versionedUrl}),
      );
      debugPrint('[AvatarUpload] Auth avatar metadata updated successfully');
      return versionedUrl;
    } on StorageException catch (error, stackTrace) {
      debugPrint(
        '[AvatarUpload] Supabase StorageException: '
        'statusCode=${error.statusCode} error=${error.error} '
        'message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[AvatarUpload] Non-storage failure: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
