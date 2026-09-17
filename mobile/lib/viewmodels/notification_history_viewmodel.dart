import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/repositories/notification_repository.dart';
import '../services/app_notification_service.dart';

enum NotificationFilter { announcement, alert, queue, message }

/// UI state and actions for the device-local Module 2 notification history.
/// Persistence remains in [NotificationHistoryStore]; this class contains no
/// widget, navigation, or dialog code.
class NotificationHistoryViewModel extends ChangeNotifier {
  NotificationHistoryViewModel({NotificationHistoryStore? store})
    : _store = store ?? NotificationHistoryStore.instance;

  final NotificationHistoryStore _store;
  StreamSubscription<void>? _changes;
  List<NotificationHistoryEntry> _entries = const [];
  bool _loading = true;
  NotificationFilter? _filter;

  List<NotificationHistoryEntry> get entries => _entries;
  bool get isLoading => _loading;
  NotificationFilter? get filter => _filter;
  List<NotificationHistoryEntry> get visibleEntries {
    final filter = _filter;
    if (filter == null) return _entries;
    return _entries
        .where(
          (entry) => switch (filter) {
            NotificationFilter.announcement =>
              entry.kind == 'announcement' || entry.kind == 'captured',
            NotificationFilter.alert => entry.kind == 'sound',
            NotificationFilter.queue => entry.kind == 'queue',
            NotificationFilter.message => entry.kind == 'request',
          },
        )
        .toList();
  }

  Future<void> initialise() async {
    _changes ??= _store.changes.listen((_) => reload());
    await reload();
  }

  Future<void> reload() async {
    final entries = await _store.entries();
    _entries = entries;
    _loading = false;
    notifyListeners();
  }

  void toggleFilter(NotificationFilter value) {
    _filter = _filter == value ? null : value;
    notifyListeners();
  }

  Future<void> markRead(NotificationHistoryEntry entry) =>
      AppNotificationService.instance.markAsRead(entry);
  Future<void> markAllRead() => AppNotificationService.instance.markAllAsRead();
  Future<void> delete(NotificationHistoryEntry entry) =>
      AppNotificationService.instance.deleteHistoryEntry(entry);
  Future<void> clear() =>
      AppNotificationService.instance.clearNotificationHistory();

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }
}
