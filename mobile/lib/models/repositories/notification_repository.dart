import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A notification the app raised, kept on the device so the in-app
/// Notifications screen can list it and deep-link to its screen even after
/// the venue session that produced it has ended.
class NotificationHistoryEntry {
  final String id;

  /// 'announcement' | 'captured' | 'queue' | 'sound'
  final String kind;
  final String title;
  final String body;

  /// Deep-link route tapped by the traveller; null rows are not tappable.
  final String? route;

  /// Android/iOS local-notification id used to dismiss the matching phone
  /// notification when this history entry is read inside the app.
  final int? notificationId;
  final DateTime createdAt;
  bool read;

  NotificationHistoryEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    this.notificationId,
    required this.createdAt,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'body': body,
    'route': route,
    'notificationId': notificationId,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
  };

  factory NotificationHistoryEntry.fromJson(Map<String, dynamic> json) =>
      NotificationHistoryEntry(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'announcement',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        route: json['route'] as String?,
        notificationId: (json['notificationId'] as num?)?.toInt(),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        read: json['read'] as bool? ?? false,
      );
}

/// Device-local history of raised notifications (oldest entries drop off).
/// Lives in SharedPreferences so both the UI isolate and the background
/// poller isolate record into the same list.
class NotificationHistoryStore {
  NotificationHistoryStore._();

  static final instance = NotificationHistoryStore._();

  static const _key = 'notification_history';
  static const _maxEntries = 50;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Notifies listeners whenever the history changes.
  Stream<void> get changes => _changes.stream;

  /// Fresh SharedPreferences instance. The plugin caches values per isolate,
  /// so without an explicit reload the UI isolate would never see entries the
  /// background poller isolate wrote while the app was inactive — the
  /// notification list would silently stay stale.
  Future<SharedPreferences> _preferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences;
  }

  Future<List<NotificationHistoryEntry>> entries() async {
    final preferences = await _preferences();
    final values = preferences.getStringList(_key) ?? const <String>[];
    return values
        .map(
          (value) => NotificationHistoryEntry.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> add(NotificationHistoryEntry entry) async {
    final preferences = await _preferences();
    final values = preferences.getStringList(_key) ?? const <String>[];
    final updated = <String>[jsonEncode(entry.toJson()), ...values];
    await preferences.setStringList(
      _key,
      updated.length > _maxEntries ? updated.sublist(0, _maxEntries) : updated,
    );
    _changes.add(null);
  }

  /// Number of unread entries — drives the red dot on the home notification
  /// button.
  Future<int> unreadCount() async {
    final entries = await this.entries();
    return entries.where((entry) => !entry.read).length;
  }

  Future<void> markRead(String id) async {
    final entries = await this.entries();
    final preferences = await _preferences();
    await preferences.setStringList(
      _key,
      entries.map((entry) {
        if (entry.id == id) entry.read = true;
        return jsonEncode(entry.toJson());
      }).toList(),
    );
    _changes.add(null);
  }

  Future<void> markAllRead() async {
    final entries = await this.entries();
    final preferences = await _preferences();
    await preferences.setStringList(
      _key,
      entries
          .map((entry) => entry..read = true)
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(),
    );
    _changes.add(null);
  }

  /// Removes one device-local notification history entry.
  Future<void> delete(String id) async {
    final entries = await this.entries();
    final preferences = await _preferences();
    await preferences.setStringList(
      _key,
      entries
          .where((entry) => entry.id != id)
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(),
    );
    _changes.add(null);
  }

  /// Clears the complete device-local notification history.
  Future<void> clear() async {
    final preferences = await _preferences();
    await preferences.remove(_key);
    _changes.add(null);
  }
}
