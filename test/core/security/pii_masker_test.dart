import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/pii_masker.dart';
import 'package:querya_desktop/core/security/pii_masking_controller.dart';

void main() {
  group('detectPiiColumn', () {
    test('recognizes the usual names', () {
      expect(detectPiiColumn('password'), PiiKind.secret);
      expect(detectPiiColumn('PASSWORD_HASH'), PiiKind.secret);
      expect(detectPiiColumn('auth_token'), PiiKind.secret);
      expect(detectPiiColumn('api_key'), PiiKind.secret);
      expect(detectPiiColumn('clientSecret'), PiiKind.secret);
      expect(detectPiiColumn('email'), PiiKind.email);
      expect(detectPiiColumn('userEmail'), PiiKind.email);
      expect(detectPiiColumn('contact_email'), PiiKind.email);
      expect(detectPiiColumn('phone'), PiiKind.phone);
      expect(detectPiiColumn('mobile_number'), PiiKind.phone);
      expect(detectPiiColumn('card_number'), PiiKind.card);
      expect(detectPiiColumn('credit_card'), PiiKind.card);
    });

    test('matches whole words only', () {
      expect(detectPiiColumn('hotel'), isNull);
      expect(detectPiiColumn('compass'), isNull);
      expect(detectPiiColumn('cardinality'), isNull);
      expect(detectPiiColumn('telegram_handle'), isNull);
    });

    test('ignores ids, counters and timestamps about a sensitive field', () {
      expect(detectPiiColumn('card_id'), isNull);
      expect(detectPiiColumn('email_verified_at'), isNull);
      expect(detectPiiColumn('password_changed_at'), isNull);
      expect(detectPiiColumn('token_count'), isNull);
    });

    test('plain data columns are not sensitive', () {
      for (final c in ['id', 'name', 'created_at', 'price', 'key', '']) {
        expect(detectPiiColumn(c), isNull, reason: c);
      }
    });

    test('detectPiiColumns maps every column', () {
      expect(
        detectPiiColumns(['id', 'email', 'password']),
        [null, PiiKind.email, PiiKind.secret],
      );
    });
  });

  group('maskPiiValue', () {
    test('secrets become dots', () {
      expect(maskPiiValue(PiiKind.secret, r'hunter2$'), kPiiMaskDots);
    });

    test('emails keep two characters and the domain', () {
      expect(maskPiiValue(PiiKind.email, 'alice@example.com'),
          'al***@example.com');
      expect(maskPiiValue(PiiKind.email, 'bo@example.com'), 'b***@example.com');
      expect(maskPiiValue(PiiKind.email, 'a@x.io'), 'a***@x.io');
    });

    test('malformed emails are fully masked', () {
      expect(maskPiiValue(PiiKind.email, 'not-an-email'), kPiiMaskDots);
      expect(maskPiiValue(PiiKind.email, '@example.com'), kPiiMaskDots);
      expect(maskPiiValue(PiiKind.email, 'alice@'), kPiiMaskDots);
    });

    test('phones keep the last two digits', () {
      expect(maskPiiValue(PiiKind.phone, '+1 (415) 555-0132'),
          '•••••••32');
      expect(maskPiiValue(PiiKind.phone, '12345'), kPiiMaskDots);
    });

    test('cards keep the last four digits', () {
      expect(maskPiiValue(PiiKind.card, '4111 1111 1111 1234'),
          '•••• •••• •••• 1234');
      expect(maskPiiValue(PiiKind.card, '4111-1111-1111-1111'),
          '•••• •••• •••• 1111');
      expect(maskPiiValue(PiiKind.card, '1234'), kPiiMaskDots);
    });

    test('NULL and empty values stay visible', () {
      for (final kind in PiiKind.values) {
        expect(maskPiiValue(kind, 'NULL'), 'NULL');
        expect(maskPiiValue(kind, ''), '');
      }
    });
  });

  group('PiiMaskingController', () {
    test('starts off, notifies on change only', () {
      final c = PiiMaskingController();
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.enabled, isFalse);
      c.enabled = false;
      expect(notified, 0);
      c.toggle();
      expect(c.enabled, isTrue);
      c.enabled = false;
      expect(notified, 2);
    });
  });
}
