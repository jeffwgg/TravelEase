import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_client.dart';
import '../models/entities/venue_session.dart';

/// Holds the traveller's venue session (FR-M2-04, FR-M2-06). The session
/// persists in SharedPreferences so official announcements keep flowing after
/// an app restart, and every screen can listen for establish/quit changes.
class VenueSessionService extends ChangeNotifier {
  VenueSessionService._();

  static final instance = VenueSessionService._();

  static const _idKey = 'venue_session_institution_id';
  static const _nameKey = 'venue_session_institution_name';
  static const _branchKey = 'venue_session_institution_branch';
  static const _serviceAreaIdKey = 'venue_session_service_area_id';
  static const _serviceAreaNameKey = 'venue_session_service_area_name';
  static const _startedAtKey = 'venue_session_started_at';

  VenueSession? _session;

  VenueSession? get session => _session;

  bool get hasActiveSession => _session != null;

  /// Establishes a session for the given institution and persists it.
  Future<void> establish(VenueSession session) async {
    _session = session;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_idKey, session.institutionId);
    await preferences.setString(_nameKey, session.institutionName);
    final branch = session.branch;
    if (branch == null || branch.isEmpty) {
      await preferences.remove(_branchKey);
    } else {
      await preferences.setString(_branchKey, branch);
    }
    final serviceAreaId = session.serviceAreaId;
    final serviceAreaName = session.serviceAreaName;
    if (serviceAreaId == null || serviceAreaName == null) {
      await preferences.remove(_serviceAreaIdKey);
      await preferences.remove(_serviceAreaNameKey);
    } else {
      await preferences.setString(_serviceAreaIdKey, serviceAreaId);
      await preferences.setString(_serviceAreaNameKey, serviceAreaName);
    }
    await preferences.setString(
      _startedAtKey,
      session.startedAt.toIso8601String(),
    );
    unawaited(_syncRemoteSession(session));
    notifyListeners();
  }

  /// Ends the active session (FR-M2-06, manual end).
  Future<void> quit() async {
    final previousSession = _session;
    _session = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_idKey);
    await preferences.remove(_nameKey);
    await preferences.remove(_branchKey);
    await preferences.remove(_serviceAreaIdKey);
    await preferences.remove(_serviceAreaNameKey);
    await preferences.remove(_startedAtKey);
    if (previousSession != null) {
      unawaited(_endRemoteSession());
    }
    notifyListeners();
  }

  /// Restores a persisted session at app start-up. A stale session without a
  /// stored institution id is discarded.
  Future<void> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final institutionId = preferences.getString(_idKey);
    if (institutionId == null) return;
    _session = VenueSession(
      institutionId: institutionId,
      institutionName: preferences.getString(_nameKey) ?? 'Connected venue',
      branch: preferences.getString(_branchKey),
      serviceAreaId: preferences.getString(_serviceAreaIdKey),
      serviceAreaName: preferences.getString(_serviceAreaNameKey),
      startedAt:
          DateTime.tryParse(preferences.getString(_startedAtKey) ?? '') ??
          DateTime.now(),
    );
    unawaited(_syncRemoteSession(_session!));
    notifyListeners();
  }

  /// Server persistence lets institution staff safely manage service areas.
  /// Local persistence remains the source for offline UX, so sync failures are
  /// deliberately best-effort and never prevent a traveller starting or ending
  /// their session.
  Future<void> _syncRemoteSession(VenueSession session) async {
    final user = SupabaseClientHelper.client.auth.currentUser;
    if (user == null) return;
    try {
      await SupabaseClientHelper.client.from('venue_sessions').upsert({
        'traveler_id': user.id,
        'institution_id': session.institutionId,
        'service_area_id': session.serviceAreaId,
        'started_at': session.startedAt.toUtc().toIso8601String(),
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'ended_at': null,
      }, onConflict: 'traveler_id');
    } catch (_) {
      // Offline use remains supported; a later restore will retry this sync.
    }
  }

  Future<void> _endRemoteSession() async {
    final user = SupabaseClientHelper.client.auth.currentUser;
    if (user == null) return;
    try {
      await SupabaseClientHelper.client
          .from('venue_sessions')
          .update({
            'ended_at': DateTime.now().toUtc().toIso8601String(),
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('traveler_id', user.id);
    } catch (_) {
      // Local end still succeeds; sync is retried if a new session is started.
    }
  }
}
