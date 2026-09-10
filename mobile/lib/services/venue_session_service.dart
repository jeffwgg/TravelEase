import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await preferences.setString(_startedAtKey, session.startedAt.toIso8601String());
    notifyListeners();
  }

  /// Ends the active session (FR-M2-06, manual end).
  Future<void> quit() async {
    _session = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_idKey);
    await preferences.remove(_nameKey);
    await preferences.remove(_branchKey);
    await preferences.remove(_startedAtKey);
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
      startedAt:
          DateTime.tryParse(preferences.getString(_startedAtKey) ?? '') ??
          DateTime.now(),
    );
    notifyListeners();
  }
}
