import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/models/entities/sos_history_entry.dart';
import 'package:travelease/models/repositories/sos_repository.dart';
import 'package:travelease/viewmodels/sos_history_viewmodel.dart';
import 'package:travelease/views/emergency/sos_history_view.dart';

Map<String, dynamic> event(String id, String date) => {
  'id': id,
  'triggered_at': date,
  'status': 'ended',
  'institution_status': 'noAffiliatedInstitution',
  'contact_status': 'notConfigured',
};

class HistoryRepository implements SosRepository {
  final auth = StreamController<bool>.broadcast(sync: true);
  List<Map<String, dynamic>> rows = [];
  bool fail = false;
  Completer<List<Map<String, dynamic>>>? pending;
  @override
  Stream<bool> get authenticatedChanges => auth.stream;
  @override
  Future<List<Map<String, dynamic>>> getHistory() async {
    if (fail) throw StateError('Offline');
    return pending == null ? rows : await pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'ending local alerts does not resolve assigned institution assistance',
    () {
      final row = event('one', '2026-09-16T10:00:00Z')
        ..addAll({
          'ended_at': '2026-09-16T10:01:00Z',
          'request': {
            'status': 'en_route',
            'staff_name': 'Responder',
            'staff_contact': '123',
          },
        });
      final entry = SosHistoryEntry.fromJson(row);
      expect(entry.progressStatus, 'en_route');
      expect(entry.assistanceOngoing, isTrue);
      expect(entry.assignedStaff, 'Responder');
      expect(historyStatusLabel(entry.progressStatus), 'On the way');
      row['request'] = {
        'status': 'resolved',
        'resolved_at': '2026-09-16T11:00:00Z',
      };
      final resolved = SosHistoryEntry.fromJson(row);
      expect(resolved.assistanceOngoing, isFalse);
      expect(resolved.assistanceSummary, 'Assistance completed');
      expect(resolved.resolvedAt, DateTime.utc(2026, 9, 16, 11));
    },
  );

  test(
    'communication entries are globally newest first, including failures',
    () async {
      final repository = HistoryRepository()
        ..rows = [
          event('one', '2026-09-16T10:00:00Z')..addAll({
            'contact_attempted_at': '2026-09-16T10:02:00Z',
            'contact_status': 'failed',
            'institution_attempted_at': '2026-09-16T10:01:00Z',
            'request': {'status': 'sent'},
          }),
          event('two', '2026-09-16T09:00:00Z')..addAll({
            'contact_attempted_at': '2026-09-16T10:03:00Z',
            'contact_status': 'pending',
          }),
        ];
      final model = SosHistoryViewModel(repository: repository);
      await model.load();
      expect(model.communications.map((entry) => entry.occurredAt.minute), [
        3,
        2,
        1,
      ]);
      expect(model.communications[1].status, 'Failed');
      model.dispose();
      await repository.auth.close();
    },
  );

  testWidgets(
    'detail refreshes progress and removes private data after sign-out',
    (tester) async {
      final repository = HistoryRepository()
        ..rows = [
          event('one', '2026-09-16T10:00:00Z')..addAll({
            'institution_name': 'Station',
            'request': {'status': 'assigned', 'staff_name': 'Responder'},
          }),
        ];
      final model = SosHistoryViewModel(repository: repository);
      await tester.pumpWidget(
        MaterialApp(
          home: SosHistoryDetailView(eventId: 'one', viewModel: model),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Assistance is ongoing'), findsOneWidget);
      expect(find.text('Staff assigned'), findsNWidgets(2));
      repository.rows[0]['request'] = {'status': 'resolved'};
      await model.load();
      await tester.pumpAndSettle();
      expect(find.text('Assistance completed'), findsOneWidget);
      repository.auth.add(false);
      await tester.pumpAndSettle();
      expect(find.text('Please sign in to view your history.'), findsOneWidget);
      expect(find.text('Assistance completed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await repository.auth.close();
    },
  );

  test('communication history includes actual attempts, not unconfigured recipients', () {
    final row = event('one', '2026-09-16T10:00:00Z');
    expect(SosHistoryEntry.fromJson(row).communications, isEmpty);
    row.addAll({
      'contact_name': 'Family',
      'contact_status': 'notified',
      'contact_attempted_at': '2026-09-16T10:00:01Z',
      'institution_name': 'Station',
      'institution_status': 'requestSent',
      'institution_attempted_at': '2026-09-16T10:00:02Z',
      'request': {'status': 'acknowledged'},
    });
    final entries = SosHistoryEntry.fromJson(row).communications;
    expect(entries.map((entry) => entry.recipient), ['Family', 'Station']);
    expect(entries.map((entry) => entry.status), [
      'Notification confirmed',
      'Acknowledged',
    ]);
  });

  test(
    'history sorts newest first, supports empty and retry after failure',
    () async {
      final repository = HistoryRepository();
      final model = SosHistoryViewModel(repository: repository);
      await model.load();
      expect(model.events, isEmpty);
      repository.fail = true;
      await model.load();
      expect(model.errorMessage, isNotNull);
      repository.fail = false;
      repository.rows = [
        event('old', '2026-09-15T10:00:00Z'),
        event('new', '2026-09-16T10:00:00Z'),
      ];
      await model.load();
      expect(model.errorMessage, isNull);
      expect(model.events.map((item) => item.id), ['new', 'old']);
      model.dispose();
      await repository.auth.close();
    },
  );

  test('sign-out discards a pending response instead of revealing the old account history', () async {
    final repository = HistoryRepository()..pending = Completer();
    final model = SosHistoryViewModel(repository: repository);
    final loading = model.load();
    repository.auth.add(false);
    repository.pending!.complete([
      event('old-account', '2026-09-16T10:00:00Z'),
    ]);
    await loading;
    expect(model.events, isEmpty);
    expect(model.errorMessage, contains('sign in'));
    model.dispose();
    await repository.auth.close();
  });
}
