import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/repositories/emergency_contact_repository.dart';
import '../models/repositories/sos_repository.dart';
import '../services/current_location_service.dart';
import '../services/live_location_service.dart';
import '../services/accessibility_alert_service.dart';

enum SosLocationStatus { pending, retrieved, unavailable }

enum SosEmergencyContactStatus { pending, notified, failed, notConfigured }

enum SosInstitutionStatus {
  pending,
  requestSent,
  noAffiliatedInstitution,
  locationUnavailable,
  failed,
}

class SosViewModel extends ChangeNotifier {
  SosViewModel({
    CurrentLocationService? locationService,
    EmergencyContactRepository? emergencyContactRepository,
    SosRepository? sosRepository,
    AccessibilityAlertService? alertService,
  }) : _locationService = locationService ?? const CurrentLocationService(),
       _emergencyContactRepository =
           emergencyContactRepository ?? EmergencyContactRepository(),
       _sosRepository = sosRepository ?? SosRepository(),
       _alertService = alertService ?? AccessibilityAlertService(),
       triggeredAt = DateTime.now().toUtc() {
    _authSubscription = _sosRepository.authenticatedChanges.listen((signedIn) {
      if (!signedIn) unawaited(endSos());
    });
  }

  final CurrentLocationService _locationService;
  final EmergencyContactRepository _emergencyContactRepository;
  final SosRepository _sosRepository;
  final DateTime triggeredAt;
  final AccessibilityAlertService _alertService;
  StreamSubscription<bool>? _authSubscription;
  bool _activated = false;
  bool _ended = false;
  Future<void>? _ending;
  Future<String?>? _historyEvent;
  Future<void> _historyWrites = Future<void>.value();

  Future<String?> _createHistory() async {
    try {
      return await _sosRepository.createHistoryEvent(triggeredAt);
    } catch (error) {
      debugPrint('[SOS] History unavailable: ${error.runtimeType}');
      return null;
    }
  }

  void _record(Map<String, dynamic> values) {
    _historyWrites = _historyWrites.then((_) async {
      try {
        var id = await _historyEvent;
        if (id == null) {
          // Retry transient creation failures using the same unique SOS time.
          _historyEvent = _createHistory();
          id = await _historyEvent;
        }
        if (id != null) await _sosRepository.updateHistoryEvent(id, values);
      } catch (error) {
        debugPrint('[SOS] History update unavailable: ${error.runtimeType}');
      }
    });
  }

  Future<void> endSos() {
    if (_ending != null) return _ending!;
    _ended = true;
    if (_activated) {
      _record({
        'status': 'ended',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    LiveLocationService.instance.stop();
    return _ending = _stopAlerts();
  }

  Future<void> _stopAlerts() async {
    try {
      await _alertService.stopSosAlerts();
    } catch (error) {
      debugPrint('[SOS] Alert cleanup failed: ${error.runtimeType}');
    }
  }

  Future<void> _startAlerts() async {
    try {
      await _alertService.startSosAlerts();
    } catch (error) {
      debugPrint('[SOS] Alerts unavailable: ${error.runtimeType}');
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed && !_ended) super.notifyListeners();
  }

  SosLocationStatus _locationStatus = SosLocationStatus.pending;
  SosEmergencyContactStatus _emergencyContactStatus =
      SosEmergencyContactStatus.pending;
  SosInstitutionStatus _institutionStatus = SosInstitutionStatus.pending;
  double? _latitude;
  double? _longitude;
  String? _locationMessage;
  bool _disposed = false;

  SosLocationStatus get locationStatus => _locationStatus;
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  String? get locationMessage => _locationMessage;
  SosEmergencyContactStatus get emergencyContactStatus =>
      _emergencyContactStatus;
  SosInstitutionStatus get institutionStatus => _institutionStatus;

  Future<void> activateSos() async {
    if (_activated || _disposed || _ended) return;
    _activated = true;
    unawaited(_startAlerts());
    _historyEvent = _createHistory();
    final result = await _locationService.getCurrentLocation();
    if (_disposed || _ended) return;
    if (result.isRetrieved) {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _locationStatus = SosLocationStatus.retrieved;
      _locationMessage = null;
    } else {
      _locationStatus = SosLocationStatus.unavailable;
      _locationMessage = result.unavailableReason;
    }
    _record({'latitude': _latitude, 'longitude': _longitude});
    notifyListeners();

    await Future.wait([_notifyEmergencyContact(), _requestInstitutionHelp()]);
    // Flush the outcomes while the active screen is alive. Emergency actions
    // above are independent of history availability.
    await _historyWrites;
  }

  Future<void> _requestInstitutionHelp() async {
    if (_disposed || _ended) return;
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) {
      if (_disposed) return;
      _institutionStatus = SosInstitutionStatus.locationUnavailable;
      _record({'institution_status': _institutionStatus.name});
      notifyListeners();
      return;
    }

    try {
      _record({
        'institution_attempted_at': DateTime.now().toUtc().toIso8601String(),
      });
      final result = await _sosRepository.matchServiceAreaAndCreateRequest(
        latitude: latitude,
        longitude: longitude,
        triggeredAt: triggeredAt,
      );
      _institutionStatus = result.result == InstitutionSosResult.requestSent
          ? SosInstitutionStatus.requestSent
          : SosInstitutionStatus.noAffiliatedInstitution;
      _record({
        'institution_status': _institutionStatus.name,
        'sos_request_id': result.sosRequestId,
        'institution_name': result.institutionName,
        'service_area_name': result.serviceAreaName,
      });
      if (_disposed || _ended) return;

      if (result.result == InstitutionSosResult.requestSent &&
          result.sosRequestId != null) {
        LiveLocationService.instance.start(
          sessionId: result.sosRequestId!,
          sessionType: 'sos',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[SOS] Institution assistance request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _institutionStatus = SosInstitutionStatus.failed;
      _record({'institution_status': _institutionStatus.name});
    }
    notifyListeners();
  }

  Future<void> _notifyEmergencyContact() async {
    try {
      final contact = await _emergencyContactRepository
          .getPreferredVerifiedContact();
      if (_disposed || _ended) return;
      if (contact == null) {
        _emergencyContactStatus = SosEmergencyContactStatus.notConfigured;
        _record({'contact_status': _emergencyContactStatus.name});
        notifyListeners();
        return;
      }

      _record({
        'contact_name': contact.name,
        'contact_attempted_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _emergencyContactRepository.sendSosNotification(
        contactId: contact.id,
        triggeredAt: triggeredAt,
        latitude: _latitude,
        longitude: _longitude,
      );
      _emergencyContactStatus = SosEmergencyContactStatus.notified;
      _record({'contact_status': _emergencyContactStatus.name});
    } catch (error, stackTrace) {
      debugPrint('[SOS] Emergency contact notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _emergencyContactStatus = SosEmergencyContactStatus.failed;
      _record({'contact_status': _emergencyContactStatus.name});
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(endSos());
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
