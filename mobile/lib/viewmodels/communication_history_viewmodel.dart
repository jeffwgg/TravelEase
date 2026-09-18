import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/supabase_client.dart';
import '../models/entities/conversation_log_entity.dart';
import '../models/repositories/communication_repository.dart';

/// Browses saved translations without starting microphone or speech services.
class CommunicationHistoryViewModel extends ChangeNotifier {
  final _repository = CommunicationRepository();
  final _client = SupabaseClientHelper.client;
  StreamSubscription<dynamic>? _auth;
  bool _disposed = false;
  int _generation = 0;
  bool isLoadingLogs = false;
  List<ConversationLog> savedLogs = [];

  CommunicationHistoryViewModel() {
    _auth = _client.auth.onAuthStateChange.listen((_) {
      savedLogs = [];
      unawaited(loadSavedLogs());
    });
  }

  Future<void> loadSavedLogs() async {
    final generation = ++_generation;
    final owner = _client.auth.currentUser?.id;
    isLoadingLogs = true;
    notifyListeners();
    final rows = owner == null
        ? <ConversationLog>[]
        : await _repository.getSavedLogs(userId: owner);
    if (_disposed || generation != _generation) return;
    savedLogs = rows..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    isLoadingLogs = false;
    notifyListeners();
  }

  Future<void> deleteSavedLog(String id) async {
    await _repository.deleteConversationLog(id);
    if (!_disposed) await loadSavedLogs();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
