import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/models/repositories/feature_usage_repository.dart';

void main() {
  test(
    'all tracked features use the database keys defined by the migration',
    () {
      expect(
        TrackedFeature.values.map((feature) => feature.key),
        containsAll(<String>[
          'sign_translate',
          'speech_to_sign',
          'two_way_dialogue',
          'sign_dictionary',
          'request_help',
          'queue_tracking',
          'announcements',
          'gps_location',
          'sos',
        ]),
      );
      expect(
        TrackedFeature.values.map((feature) => feature.key).toSet(),
        hasLength(9),
      );
    },
  );

  test('all tracked events use the database keys defined by the RPC', () {
    expect(
      FeatureUsageEvent.values.map((event) => event.key),
      containsAll(<String>['opened', 'completed']),
    );
  });
}
