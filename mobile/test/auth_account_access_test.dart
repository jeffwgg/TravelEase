import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:travelease/models/repositories/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final allowed in [true, false, null]) {
    test('login validates linked traveller account: $allowed', () async {
      var validated = false;
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'refresh_token': 'test-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': '00000000-0000-0000-0000-000000000001',
                  'aud': 'authenticated',
                  'email': 'account@example.test',
                  'app_metadata': {},
                  'user_metadata': {'account_type': 'traveller'},
                  'created_at': '2026-09-18T00:00:00Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.endsWith('/rpc/is_traveller_account')) {
            validated = true;
            if (allowed == null) {
              return http.Response(
                '{"message":"Access check unavailable"}',
                503,
                request: request,
              );
            }
            return http.Response(
              jsonEncode(allowed),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.endsWith('/logout')) {
            return http.Response('{}', 200, request: request);
          }
          return http.Response('Unexpected request', 500, request: request);
        }),
      );
      final repository = AuthRepository(client: client);
      try {
        final login = repository.signIn(
          email: 'account@example.test',
          password: 'Password123',
        );
        if (allowed == true) {
          expect((await login).session, isNotNull);
          expect(repository.currentSession, isNotNull);
          // Restored sessions and password changes reuse this same validation.
          await repository.validateTravellerSession();
        } else if (allowed == false) {
          await expectLater(
            login,
            throwsA(
              isA<AuthException>().having(
                (error) => error.message,
                'message',
                AuthRepository.travellerAccessMessage,
              ),
            ),
          );
          expect(repository.currentSession, isNull);
        } else {
          await expectLater(login, throwsA(isA<PostgrestException>()));
          expect(
            repository.currentSession,
            isNull,
            reason:
                'A failed access check must not leave an authorized session',
          );
        }
        expect(validated, isTrue);
      } finally {
        await client.dispose();
      }
    });
  }
}
