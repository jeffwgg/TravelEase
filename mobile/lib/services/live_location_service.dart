import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/supabase_client.dart';

class LiveLocationService {
  LiveLocationService._();
  static final LiveLocationService instance = LiveLocationService._();

  Timer? _timer;
  String? _activeSessionId;
  String? _activeSessionType; // 'assistance' | 'sos'
  Position? _lastPublishedPosition;
  bool _isUpdating = false;

  bool get isRunning => _timer != null && _activeSessionId != null;
  String? get activeSessionId => _activeSessionId;
  String? get activeSessionType => _activeSessionType;

  /// Starts periodic 10-second location tracking.
  /// Distance gate: 8 meters. If the traveler moved < 8 meters, skips DB push.
  Future<void> start({
    required String sessionId,
    required String sessionType,
  }) async {
    if (_activeSessionId == sessionId && isRunning) {
      debugPrint('[LiveLocationService] Already tracking for $sessionType: $sessionId');
      return;
    }

    if (isRunning) {
      await stop();
    }

    _activeSessionId = sessionId;
    _activeSessionType = sessionType;
    _lastPublishedPosition = null;

    debugPrint('[LiveLocationService] Starting live tracking for $sessionType: $sessionId');

    // Immediate initial push
    await _checkAndPublishLocation();

    // Periodic check every 10 seconds
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkAndPublishLocation();
    });
  }

  Future<void> _checkAndPublishLocation() async {
    if (_activeSessionId == null || _isUpdating) return;
    _isUpdating = true;

    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        debugPrint('[LiveLocationService] Location service disabled');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('[LiveLocationService] Location permission denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      // Distance gate check (8 meters threshold)
      if (_lastPublishedPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPublishedPosition!.latitude,
          _lastPublishedPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        if (distance < 8.0) {
          debugPrint(
            '[LiveLocationService] Traveler moved only ${distance.toStringAsFixed(1)}m (< 8m). Skipping push to conserve quota.',
          );
          return;
        }
      }

      // Upsert to Supabase traveler_live_locations
      final client = SupabaseClientHelper.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[LiveLocationService] No authenticated user. Cannot push location.');
        return;
      }

      await client.from('traveler_live_locations').upsert({
        'session_id': _activeSessionId,
        'session_type': _activeSessionType,
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_m': position.accuracy,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      _lastPublishedPosition = position;
      debugPrint(
        '[LiveLocationService] Published live location for $_activeSessionId: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} (±${position.accuracy.toStringAsFixed(1)}m)',
      );
    } catch (e) {
      debugPrint('[LiveLocationService] Error updating location: $e');
    } finally {
      _isUpdating = false;
    }
  }

  /// Stops tracking and removes the live location record from DB
  Future<void> stop() async {
    final sessionId = _activeSessionId;
    _timer?.cancel();
    _timer = null;
    _activeSessionId = null;
    _activeSessionType = null;
    _lastPublishedPosition = null;

    if (sessionId != null) {
      try {
        final client = SupabaseClientHelper.client;
        await client
            .from('traveler_live_locations')
            .delete()
            .eq('session_id', sessionId);
        debugPrint('[LiveLocationService] Stopped tracking and cleaned up row for $sessionId');
      } catch (e) {
        debugPrint('[LiveLocationService] Error removing location record: $e');
      }
    }
  }
}
