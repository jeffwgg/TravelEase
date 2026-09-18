import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class AuthRepository {
  AuthRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String fullName,
    required String nationality,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'travelease://auth/callback',
      data: {
        'full_name': fullName,
        'nationality': nationality,
        'account_type': 'traveller',
      },
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    try {
      await validateTravellerSession();
      return response;
    } catch (_) {
      await _client.auth.signOut(scope: SignOutScope.local);
      rethrow;
    }
  }

  static const travellerAccessMessage =
      'This account is not registered as a traveller.';

  Future<void> validateTravellerSession() async {
    if (_client.auth.currentUser == null ||
        await _client.rpc('is_traveller_account') != true) {
      throw const AuthException(travellerAccessMessage);
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'travelease://auth/reset-password',
    );
  }

  Future<UserResponse> updatePassword(String password) async {
    await validateTravellerSession();
    return _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() => _client.auth.signOut();

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;
}
