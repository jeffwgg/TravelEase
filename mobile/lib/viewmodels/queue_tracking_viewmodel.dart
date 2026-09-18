import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/queue_tracking.dart';
import '../models/repositories/feature_usage_repository.dart';
import '../models/repositories/queue_repository.dart';
import '../services/queue_notification_service.dart';
import '../services/venue_session_service.dart';

/// State and use-cases for the Module 2 queue-tracking workflow.
class QueueTrackingViewModel extends ChangeNotifier {
  QueueTrackingViewModel({QueueRepository? repository})
    : _repository = repository ?? QueueRepository();

  final QueueRepository _repository;

  List<QueueLineInfo> lines = const [];
  QueueTrackingData? tracking;
  RealtimeChannel? channel;
  String? selectedLineId;
  String? error;
  String? loadError;
  bool loadingLines = true;
  bool trackingNumber = false;

  /// Incremented when a persisted tracking number should be restored to the
  /// view-owned text field.
  int numberPrefillRevision = 0;
  String? numberToPrefill;

  bool _disposed = false;
  Timer? _refreshTimer;
  bool _refreshing = false;

  static const _refreshInterval = Duration(seconds: 15);

  QueueLineInfo? get selectedLine {
    for (final line in lines) {
      if (line.id == selectedLineId) return line;
    }
    return null;
  }

  Future<void> initialize() async {
    FeatureUsageTracker.instance.opened(TrackedFeature.queueTracking);
    await loadLines();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (tracking != null) unawaited(refreshTracking());
    });
  }

  void selectLine(String? lineId) {
    if (selectedLineId == lineId) return;
    selectedLineId = lineId;
    _notify();
  }

  /// Realtime events raised while the app is suspended are only picked up
  /// when it resumes, so refresh the tracked number on return.
  Future<void> refreshForAppResume() =>
      tracking == null ? loadLines() : refreshTracking();

  Future<void> loadLines() async {
    final session = VenueSessionService.instance.session;
    final institutionId = session?.institutionId;
    final serviceAreaId = session?.serviceAreaId;
    if (institutionId == null || serviceAreaId == null) {
      lines = const [];
      tracking = null;
      selectedLineId = null;
      loadingLines = false;
      error = null;
      loadError = null;
      _notify();
      return;
    }

    final needsInitialLoad = lines.isEmpty && tracking == null;
    if (needsInitialLoad) {
      loadingLines = true;
      loadError = null;
      _notify();
    }
    try {
      final loadedLines = await _repository.getActiveQueueLines(
        institutionId: institutionId,
        serviceAreaId: serviceAreaId,
      );
      if (_disposed) return;
      lines = loadedLines;
      loadError = null;
      loadingLines = false;
      if (!loadedLines.any((line) => line.id == selectedLineId)) {
        tracking = null;
        selectedLineId = null;
      }
      _notify();

      final saved = QueueNotificationService.instance.current;
      final savedLineIsHere =
          saved != null && loadedLines.any((line) => line.id == saved.line.id);
      if (saved != null && savedLineIsHere && !_disposed) {
        numberToPrefill = saved.number;
        numberPrefillRevision++;
        tracking = saved;
        selectedLineId = saved.line.id;
        await _replaceTrackingSubscription(saved.line.id);
        _notify();
      }
    } catch (_) {
      if (_disposed) return;
      loadError = 'Unable to load queue lines. Please try again.';
      loadingLines = false;
      _notify();
    }
  }

  Future<void> trackNumber(String rawNumber) async {
    final session = VenueSessionService.instance.session;
    final institutionId = session?.institutionId;
    final serviceAreaId = session?.serviceAreaId;
    if (institutionId == null || serviceAreaId == null) {
      error =
          'Start a venue session with a service area before tracking a queue.';
      _notify();
      return;
    }
    final number = rawNumber.trim();
    if (number.isEmpty) {
      error = 'Enter your queue number.';
      _notify();
      return;
    }
    // Instant feedback: a number beyond the selected line's maximum queue
    // number can never be called, so do not even look it up.
    final line = selectedLine;
    if (line != null) {
      final capError = QueueRepository.maximumQueueNumberViolation(
        number,
        line,
      );
      if (capError != null) {
        error = capError;
        _notify();
        return;
      }
    }

    trackingNumber = true;
    error = null;
    _notify();
    try {
      final found = await _repository.trackNumber(
        number: number,
        queueLineId: selectedLineId,
        queuePrefix: line?.prefix,
        institutionId: institutionId,
        serviceAreaId: serviceAreaId,
      );
      if (_disposed) return;
      if (found == null) {
        error = 'Queue number not found. Check the number and queue line.';
        return;
      }
      final result = await _repository.storeTrackedWaitingNumber(
        found,
        institutionId: institutionId,
        serviceAreaId: serviceAreaId,
      );
      if (_disposed) return;
      await _replaceTrackingSubscription(result.line.id);
      if (_disposed) return;
      tracking = result;
      selectedLineId = result.line.id;
      _notify();
      await QueueNotificationService.instance.track(result);
      FeatureUsageTracker.instance.completed(TrackedFeature.queueTracking);
    } on QueueNumberBeyondMaximumException catch (exception) {
      if (_disposed) return;
      error = exception.message;
    } catch (_) {
      if (_disposed) return;
      error = 'Unable to track this queue number right now.';
    } finally {
      if (!_disposed) {
        trackingNumber = false;
        _notify();
      }
    }
  }

  Future<void> refreshTracking() async {
    final current = tracking;
    final session = VenueSessionService.instance.session;
    final institutionId = session?.institutionId;
    final serviceAreaId = session?.serviceAreaId;
    if (_refreshing ||
        current == null ||
        institutionId == null ||
        serviceAreaId == null) {
      return;
    }
    _refreshing = true;
    try {
      final result = await _repository.trackNumber(
        number: current.number,
        queueLineId: current.line.id,
        queuePrefix: current.line.prefix,
        institutionId: institutionId,
        serviceAreaId: serviceAreaId,
      );
      if (_disposed) return;
      if (result != null) {
        tracking = result;
        loadError = null;
      } else {
        loadError = 'Unable to refresh this queue number. Showing the last known status.';
      }
    } catch (_) {
      if (_disposed) return;
      loadError =
          'Unable to refresh this queue number. Showing the last known status.';
    } finally {
      _refreshing = false;
    }
    _notify();
  }

  Future<void> _replaceTrackingSubscription(String queueLineId) async {
    final previous = channel;
    channel = null;
    if (previous != null) await _repository.removeSubscription(previous);
    if (_disposed) return;
    channel = _repository.subscribeToTracking(queueLineId, refreshTracking);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final activeChannel = channel;
    channel = null;
    if (activeChannel != null) {
      unawaited(_repository.removeSubscription(activeChannel));
    }
    super.dispose();
  }
}
