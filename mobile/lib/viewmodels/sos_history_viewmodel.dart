import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/entities/sos_history_entry.dart';
import '../models/repositories/sos_repository.dart';

class SosHistoryViewModel extends ChangeNotifier {
  SosHistoryViewModel({SosRepository? repository})
    : _repository = repository ?? SosRepository() {
    _authSubscription = _repository.authenticatedChanges.listen((signedIn) {
      // Invalidate cached data and outstanding loads on every auth event,
      // including switching directly to a different signed-in account.
      _generation++;
      events = [];
      isLoading = false;
      errorMessage = signedIn ? null : 'Please sign in to view your history.';
      if (!_disposed) notifyListeners();
      if (signedIn && !_disposed) unawaited(load());
    });
  }

  final SosRepository _repository;
  StreamSubscription<bool>? _authSubscription;
  bool _disposed = false;
  int _generation = 0;
  bool isLoading = false;
  String? errorMessage;
  List<SosHistoryEntry> events = [];

  List<EmergencyCommunicationEntry> get communications {
    final result = events.expand((event) => event.communications).toList();
    result.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return result;
  }

  Future<void> load({bool quiet = false}) async {
    if (_disposed) return;
    final generation = ++_generation;
    isLoading = !quiet;
    errorMessage = null;
    notifyListeners();
    try {
      final rows = await _repository.getHistory();
      if (_disposed || generation != _generation) return;
      events = rows.map(SosHistoryEntry.fromJson).toList()
        ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    } catch (_) {
      if (_disposed || generation != _generation) return;
      errorMessage = 'Unable to load your history. Please try again.';
    }
    if (_disposed || generation != _generation) return;
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
