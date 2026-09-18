import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_client.dart';
import '../entities/announcement.dart';
import '../entities/spoken_announcement.dart';

/// Device-local storage for microphone-captured public announcements. No
/// Supabase table is introduced: captures live in SharedPreferences on the
/// traveller's device and are capped so the oldest entries age out.
class CapturedAnnouncementStore {
  CapturedAnnouncementStore._();

  static final instance = CapturedAnnouncementStore._();

  static const _storageKeyPrefix = 'captured_announcements:';
  static const _maxEntries = 30;

  /// Bumped whenever a capture is added so open announcement lists reload.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  String get _storageKey =>
      '$_storageKeyPrefix${SupabaseClientHelper.client.auth.currentUser?.id ?? 'guest'}';

  Future<List<CapturedAnnouncement>> _loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_storageKey) ?? const [];
    return values
        .map(
          (value) => CapturedAnnouncement.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> _saveAll(List<CapturedAnnouncement> entries) async {
    final preferences = await SharedPreferences.getInstance();
    final limited = entries
        .take(_maxEntries)
        .map((entry) => jsonEncode(entry.toJson()))
        .toList();
    await preferences.setStringList(_storageKey, limited);
  }

  /// All locally captured spoken announcements, newest first.
  Future<List<CapturedAnnouncement>> all() async {
    final entries = await _loadAll();
    entries.sort((a, b) => b.lastCapturedAt.compareTo(a.lastCapturedAt));
    return entries;
  }

  /// Device-wide spoken announcements rendered through the shared
  /// [Announcement] entity.
  Future<List<Announcement>> announcements() async {
    final entries = await all();
    return entries.map((entry) => entry.toAnnouncement()).toList();
  }

  Future<CapturedAnnouncement?> byId(String id) async {
    final entries = await _loadAll();
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Inserts or merges a capture. When a matching capture already exists the
  /// repetition count and confidence are strengthened instead of duplicating
  /// the entry.
  Future<void> upsert(CapturedAnnouncement capture) async {
    final entries = await _loadAll();
    final index = entries.indexWhere((entry) => entry.id == capture.id);
    if (index >= 0) {
      entries[index] = capture;
    } else {
      entries.insert(0, capture);
    }
    await _saveAll(entries);
    version.value++;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    version.value++;
  }
}
