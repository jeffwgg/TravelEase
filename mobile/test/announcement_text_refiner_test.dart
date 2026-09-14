import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/services/announcement_text_refiner.dart';

void main() {
  group('AnnouncementTextRefiner local formatting', () {
    test('cleans common transit abbreviations and sentence casing', () {
      final result = AnnouncementTextRefiner.formatLocally(
        'k l i a final call for flight m h one two three',
      );

      expect(result.usedAi, isFalse);
      expect(result.transcript, 'KLIA final call for flight MH123.');
      expect(result.title, 'Final boarding call');
    });

    test('creates an informative title without adding announcement facts', () {
      final result = AnnouncementTextRefiner.formatLocally(
        'the next train is arriving at platform 2',
      );

      expect(result.title, 'Arrival announcement');
      expect(result.transcript, 'The next train is arriving at Platform 2.');
    });

    test('uses local transit terms and a safe boarding template', () {
      final result = AnnouncementTextRefiner.formatLocally(
        'flight m h one two three now boarding gate b 4',
      );

      expect(result.title, 'Boarding update');
      expect(result.transcript, 'Flight MH123 is now boarding at Gate B4.');
    });

    test(
      'formats a complete train pattern without inventing a destination',
      () {
        final result = AnnouncementTextRefiner.formatLocally(
          'the next train to kuala lumpur central is arriving at platform 2',
        );

        expect(result.title, 'Arrival announcement');
        expect(
          result.transcript,
          'The next train to KL Sentral is arriving at Platform 2.',
        );
      },
    );

    test(
      'repairs a wrapped boarding phrase without inventing missing facts',
      () {
        final result = AnnouncementTextRefiner.formatLocally(
          'boarding begins in ten minutes ladies and gentlemen passengers for floght m h one two three',
        );

        expect(result.title, 'Boarding update');
        expect(
          result.transcript,
          'Ladies and gentlemen, passengers for flight MH123. Boarding begins in 10 minutes.',
        );
      },
    );

    test('uses a concise fallback title instead of the raw transcript', () {
      final result = AnnouncementTextRefiner.formatLocally(
        'please collect your items from the information desk',
      );

      expect(result.title, 'Spoken announcement');
      expect(
        result.transcript,
        'Please collect your items from the information desk.',
      );
    });
  });
}
