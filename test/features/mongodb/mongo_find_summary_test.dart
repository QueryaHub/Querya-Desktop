import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/mongodb/mongo_query_executor.dart';

void main() {
  group('mongoFindSummary (#1357)', () {
    test('an ordinary find just says how many documents came back', () {
      expect(mongoFindSummary(25, null), 'Fetched 25 documents');
      expect(mongoFindSummary(100, 100), 'Fetched 100 documents');
      expect(mongoFindSummary(kMongoDefaultFindLimit, 5000), 'Fetched 1000 documents');
    });

    test('.limit(0) that hit the cap says so', () {
      expect(
        mongoFindSummary(kMongoDefaultFindLimit, 0),
        contains('capped at $kMongoDefaultFindLimit'),
      );
    });

    test('.limit(0) that did not reach the cap is not marked', () {
      expect(mongoFindSummary(12, 0), 'Fetched 12 documents');
    });
  });
}
