import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/services/announcement_keyword_scorer.dart';

void main() {
  const scorer = AnnouncementKeywordScorer();

  group('AnnouncementKeywordScorer common PA wording', () {
    test('recognises an arrival announcement', () {
      final result = scorer.score(
        'Attention passengers. We have now reached the destination. '
        'We hope you enjoy the flight and have a nice day.',
        0.5,
      );

      expect(result.isAnnouncement, isTrue);
      expect(result.keywordHits, greaterThanOrEqualTo(2));
    });

    test('recognises a boarding instruction with a spoken flight number', () {
      final result = scorer.score(
        'Ladies and gentlemen, passengers for flight MH one two three to '
        'Penang should proceed to gate B twelve. Boarding begins in ten minutes.',
        0.5,
      );

      expect(result.isAnnouncement, isTrue);
      expect(result.keywordHits, greaterThanOrEqualTo(3));
    });
  });
}
