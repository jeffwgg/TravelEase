import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class AuthRepository {
  static const emailCallbackUrl = 'travelease://auth/callback';

  AuthRepository({SupabaseClient? client})
      : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String fullName,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailCallbackUrl,
      data: {'full_name': fullName},
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;
}
