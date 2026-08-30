import 'dart:async';

import 'package:app_links/app_links.dart';
import '../core/supabase_client.dart';

class AuthDeepLinkService {
  AuthDeepLinkService._();

  static final instance = AuthDeepLinkService._();
  static const _callbackUri = 'travelease://auth/callback';
  static const _passwordResetUri = 'travelease://auth/reset-password';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  String? _lastHandledLink;
  bool _isHandling = false;

  Future<void> initialize({
    required Future<void> Function(bool isPasswordRecovery) onAuthSession,
  }) async {
    if (_subscription != null) return;

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _handle(uri, onAuthSession),
    );

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      await _handle(initialUri, onAuthSession);
    }
  }

  Future<void> _handle(
    Uri uri,
    Future<void> Function(bool isPasswordRecovery) onAuthSession,
  ) async {
    if (!_isAuthCallback(uri) ||
        _isHandling ||
        _lastHandledLink == uri.toString()) {
      return;
    }

    _isHandling = true;
    try {
      final hasSession = await _waitForSupabaseSession();
      if (!hasSession) return;
      _lastHandledLink = uri.toString();
      await onAuthSession(_isPasswordRecovery(uri));
    } finally {
      _isHandling = false;
    }
  }

  bool _isAuthCallback(Uri uri) =>
      uri.scheme == 'travelease' &&
      uri.host == 'auth' &&
      ((uri.path == '/callback' && uri.toString().startsWith(_callbackUri)) ||
          (uri.path == '/reset-password' &&
              uri.toString().startsWith(_passwordResetUri)));

  bool _isPasswordRecovery(Uri uri) {
    if (uri.path == '/reset-password') return true;
    if (uri.queryParameters['type'] == 'recovery') return true;
    if (uri.fragment.isEmpty) return false;
    return Uri.splitQueryString(uri.fragment)['type'] == 'recovery';
  }

  Future<bool> _waitForSupabaseSession() async {
    final auth = SupabaseClientHelper.client.auth;
    if (auth.currentUser != null && auth.currentSession != null) return true;

    try {
      final state = await auth.onAuthStateChange
          .firstWhere(
            (state) => state.session != null && state.session?.user != null,
          )
          .timeout(const Duration(seconds: 10));
      return state.session != null;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
