import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Stores completion of the complete TravelEase tour against the signed-in
/// account.
///
/// User metadata is used deliberately instead of a device-only preference, so
/// finishing the tour on one device also prevents it from appearing again on
/// another device. The local value makes the result available immediately and
/// keeps the tour from repeating while the device is offline.
class HomeGuidanceRepository {
  HomeGuidanceRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  // Version 1 covered only Home. Version 2 adds the feature-by-feature tour,
  // so people who completed the original guide can see the new one once.
  static const homeTourVersion = 2;
  static const _metadataKey = 'travelease_home_tour_version';
  static const _localKeyPrefix = 'travelease.home_tour_version';

  final SupabaseClient _client;

  Future<bool> shouldShowHomeTour() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final localVersion = (await SharedPreferences.getInstance()).getInt(
      _localKeyFor(user.id),
    );
    if (localVersion == homeTourVersion) {
      // Retry an earlier cloud write without delaying the home screen.
      unawaited(_syncCompletion(user));
      return false;
    }

    final remoteVersion = user.userMetadata?[_metadataKey];
    if (_isCompletedVersion(remoteVersion)) {
      await _saveLocalCompletion(user.id);
      return false;
    }
    return true;
  }

  Future<void> markHomeTourComplete() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _saveLocalCompletion(user.id);
    await _syncCompletion(user);
  }

  String _localKeyFor(String userId) => '${_localKeyPrefix}_$userId';

  Future<void> _saveLocalCompletion(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_localKeyFor(userId), homeTourVersion);
  }

  Future<void> _syncCompletion(User user) async {
    if (_isCompletedVersion(user.userMetadata?[_metadataKey])) return;
    try {
      await _client.auth.updateUser(
        UserAttributes(
          data: {...?user.userMetadata, _metadataKey: homeTourVersion},
        ),
      );
    } catch (_) {
      // Local completion is intentional fall-back behaviour. The next signed
      // in launch retries this account-level write when connectivity returns.
    }
  }

  bool _isCompletedVersion(Object? value) {
    return value is num && value.toInt() >= homeTourVersion;
  }
}
