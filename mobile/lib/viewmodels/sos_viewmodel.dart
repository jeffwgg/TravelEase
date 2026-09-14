import 'package:flutter/foundation.dart';

import '../models/repositories/emergency_contact_repository.dart';
import '../models/repositories/sos_repository.dart';
import '../services/current_location_service.dart';
import '../services/live_location_service.dart';

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
  }) : _locationService = locationService ?? const CurrentLocationService(),
       _emergencyContactRepository =
           emergencyContactRepository ?? EmergencyContactRepository(),
       _sosRepository = sosRepository ?? SosRepository(),
       triggeredAt = DateTime.now().toUtc();

  final CurrentLocationService _locationService;
  final EmergencyContactRepository _emergencyContactRepository;
  final SosRepository _sosRepository;
  final DateTime triggeredAt;

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
    final result = await _locationService.getCurrentLocation();
    if (_disposed) return;
    if (result.isRetrieved) {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _locationStatus = SosLocationStatus.retrieved;
      _locationMessage = null;
    } else {
      _locationStatus = SosLocationStatus.unavailable;
      _locationMessage = result.unavailableReason;
    }
    notifyListeners();

    await Future.wait([_notifyEmergencyContact(), _requestInstitutionHelp()]);
  }

  Future<void> _requestInstitutionHelp() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) {
      if (_disposed) return;
      _institutionStatus = SosInstitutionStatus.locationUnavailable;
      notifyListeners();
      return;
    }

    try {
      final result = await _sosRepository.matchServiceAreaAndCreateRequest(
        latitude: latitude,
        longitude: longitude,
        triggeredAt: triggeredAt,
      );
      if (_disposed) return;
      _institutionStatus = result.result == InstitutionSosResult.requestSent
          ? SosInstitutionStatus.requestSent
          : SosInstitutionStatus.noAffiliatedInstitution;

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
      if (_disposed) return;
      _institutionStatus = SosInstitutionStatus.failed;
    }
    notifyListeners();
  }

  Future<void> _notifyEmergencyContact() async {
    try {
      final contact = await _emergencyContactRepository
          .getPreferredVerifiedContact();
      if (_disposed) return;
      if (contact == null) {
        _emergencyContactStatus = SosEmergencyContactStatus.notConfigured;
        notifyListeners();
        return;
      }

      await _emergencyContactRepository.sendSosNotification(
        contactId: contact.id,
        triggeredAt: triggeredAt,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (_disposed) return;
      _emergencyContactStatus = SosEmergencyContactStatus.notified;
    } catch (error, stackTrace) {
      debugPrint('[SOS] Emergency contact notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_disposed) return;
      _emergencyContactStatus = SosEmergencyContactStatus.failed;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    LiveLocationService.instance.stop();
    super.dispose();
  }
}
