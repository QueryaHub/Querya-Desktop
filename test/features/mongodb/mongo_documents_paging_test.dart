import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_view.dart';

void main() {
  group('mongoExactTotalFromPage', () {
    test('a short first page pins the total without a count', () {
      expect(mongoExactTotalFromPage(skip: 0, limit: 25, pageLength: 7), 7);
      expect(mongoExactTotalFromPage(skip: 0, limit: 25, pageLength: 0), 0);
    });

    test('a short later page pins skip + length', () {
      expect(mongoExactTotalFromPage(skip: 50, limit: 25, pageLength: 3), 53);
    });

    test('a full page leaves the total unknown', () {
      expect(mongoExactTotalFromPage(skip: 0, limit: 25, pageLength: 25),
          isNull);
      expect(mongoExactTotalFromPage(skip: 25, limit: 25, pageLength: 25),
          isNull);
    });

    test('an empty page past the start leaves the total unknown', () {
      expect(mongoExactTotalFromPage(skip: 75, limit: 25, pageLength: 0),
          isNull);
    });
  });

  group('mongoHasNextPage', () {
    test('uses the known total', () {
      expect(
        mongoHasNextPage(skip: 0, limit: 25, pageLength: 25, total: 25),
        isFalse,
      );
      expect(
        mongoHasNextPage(skip: 0, limit: 25, pageLength: 25, total: 26),
        isTrue,
      );
      expect(
        mongoHasNextPage(skip: 25, limit: 25, pageLength: 1, total: 26),
        isFalse,
      );
    });

    test('assumes more while the count is pending and the page is full', () {
      expect(mongoHasNextPage(skip: 0, limit: 25, pageLength: 25), isTrue);
      expect(mongoHasNextPage(skip: 0, limit: 25, pageLength: 24), isFalse);
    });
  });
}
