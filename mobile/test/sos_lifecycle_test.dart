import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/models/entities/emergency_contact.dart';
import 'package:travelease/models/repositories/emergency_contact_repository.dart';
import 'package:travelease/models/repositories/sos_repository.dart';
import 'package:travelease/services/accessibility_alert_service.dart';
import 'package:travelease/services/current_location_service.dart';
import 'package:travelease/viewmodels/sos_viewmodel.dart';

class FakeAlerts extends AccessibilityAlertService {
  int starts = 0;
  int stops = 0;
  bool fail = false;
  @override
  Future<void> startSosAlerts() async {
    starts++;
    if (fail) throw StateError('No hardware');
  }

  @override
  Future<void> stopSosAlerts() async {
    stops++;
  }
}

class FakeLocation extends CurrentLocationService {
  final Completer<CurrentLocationResult> result = Completer();
  @override
  Future<CurrentLocationResult> getCurrentLocation() => result.future;
}

class FakeContacts implements EmergencyContactRepository {
  int sends = 0;
  @override
  Future<EmergencyContact?> getPreferredVerifiedContact() async =>
      const EmergencyContact(
        id: 'contact',
        userId: 'owner',
        name: 'Contact',
        relationship: 'Family',
        phoneNumber: '',
        email: '',
        isPrimary: true,
        isVerified: true,
      );
  @override
  Future<void> sendSosNotification({
    required String contactId,
    required DateTime triggeredAt,
    double? latitude,
    double? longitude,
  }) async {
    sends++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSos implements SosRepository {
  final auth = StreamController<bool>.broadcast(sync: true);
  final updates = <Map<String, dynamic>>[];
  int requests = 0;
  bool failHistory = false;
  @override
  Stream<bool> get authenticatedChanges => auth.stream;
  @override
  Future<String> createHistoryEvent(DateTime triggeredAt) async {
    if (failHistory) throw StateError('History unavailable');
    return 'event';
  }

  @override
  Future<void> updateHistoryEvent(
    String id,
    Map<String, dynamic> values,
  ) async {
    updates.add(values);
  }

  @override
  Future<InstitutionSosResponse> matchServiceAreaAndCreateRequest({
    required double latitude,
    required double longitude,
    required DateTime triggeredAt,
  }) async {
    requests++;
    return const InstitutionSosResponse(result: InstitutionSosResult.noMatch);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAlerts alerts;
  late FakeLocation location;
  late FakeContacts contacts;
  late FakeSos repository;
  late SosViewModel model;
  bool disposed = false;
  setUp(() {
    disposed = false;
    alerts = FakeAlerts();
    location = FakeLocation();
    contacts = FakeContacts();
    repository = FakeSos();
    model = SosViewModel(
      locationService: location,
      emergencyContactRepository: contacts,
      sosRepository: repository,
      alertService: alerts,
    );
  });
  tearDown(() async {
    if (!disposed) model.dispose();
    await repository.auth.close();
  });

  test('construction/countdown never starts alerts', () {
    expect(alerts.starts, 0);
    expect(repository.requests, 0);
  });

  test('activation is idempotent and ending during location lookup prevents late sends', () async {
    final activation = model.activateSos();
    await model.activateSos();
    expect(alerts.starts, 1);
    await model.endSos();
    await model.endSos();
    location.result.complete(
      const CurrentLocationResult.retrieved(latitude: 1, longitude: 2),
    );
    await activation;
    await Future<void>.delayed(Duration.zero);
    expect(alerts.stops, 1);
    expect(contacts.sends, 0);
    expect(repository.requests, 0);
    expect(repository.updates.any((row) => row['status'] == 'ended'), isTrue);
  });

  test(
    'alert and history failures do not block contact or institution flow',
    () async {
      alerts.fail = true;
      repository.failHistory = true;
      location.result.complete(
        const CurrentLocationResult.retrieved(latitude: 1, longitude: 2),
      );
      await model.activateSos();
      expect(contacts.sends, 1);
      expect(repository.requests, 1);
      expect(model.emergencyContactStatus, SosEmergencyContactStatus.notified);
      expect(
        model.institutionStatus,
        SosInstitutionStatus.noAffiliatedInstitution,
      );
    },
  );

  test(
    'missing location still notifies the contact and sign-out stops alerts',
    () async {
      location.result.complete(
        const CurrentLocationResult.unavailable('Denied'),
      );
      await model.activateSos();
      expect(contacts.sends, 1);
      expect(repository.requests, 0);
      expect(alerts.stops, 0);
      repository.auth.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(alerts.stops, 1);
    },
  );

  test('disposing while active stops alerts', () async {
    location.result.complete(const CurrentLocationResult.unavailable('Denied'));
    await model.activateSos();
    model.dispose();
    disposed = true;
    await Future<void>.delayed(Duration.zero);
    expect(alerts.stops, 1);
  });

  test('contact recipient, attempt and confirmed outcome are persisted before activation completes', () async {
    location.result.complete(const CurrentLocationResult.unavailable('Denied'));
    await model.activateSos();
    final saved = <String, dynamic>{};
    for (final update in repository.updates) {
      saved.addAll(update);
    }
    expect(saved['contact_name'], 'Contact');
    expect(
      DateTime.tryParse(saved['contact_attempted_at'] as String),
      isNotNull,
    );
    expect(saved['contact_status'], 'notified');
    expect(saved['institution_status'], 'locationUnavailable');
  });
}
