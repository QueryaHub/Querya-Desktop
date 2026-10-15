import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/pii_masker.dart';

/// `detectPiiColumn` and `maskPiiValue` as they were before #1540 / #1516
/// (regex, replaceAll, split / join): the reference the scanners must match.
List<String> _refTokens(String name) {
  final spaced = name
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ');
  return spaced.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
}

PiiKind? _refDetect(String columnName) {
  const secret = {
    'password', 'passwd', 'pwd', 'pass', 'passcode', 'passphrase', 'token',
    'secret', 'apikey', 'hash', 'salt',
  };
  const email = {'email', 'mail'};
  const phone = {'phone', 'mobile', 'cell', 'tel', 'telephone', 'msisdn', 'fax'};
  const card = {'card', 'cc', 'pan', 'iban'};
  final tokens = _refTokens(columnName);
  if (tokens.isEmpty) return null;
  final joined = tokens.join('_');
  if (RegExp(r'(^|_)(api|private|access|secret|auth)_key($|_)')
      .hasMatch(joined)) {
    return PiiKind.secret;
  }
  const meta = {'at', 'verified', 'confirmed', 'sent', 'count', 'id'};
  if (meta.contains(tokens.last) && tokens.length > 1) return null;
  for (final t in tokens) {
    if (secret.contains(t)) return PiiKind.secret;
    if (card.contains(t)) return PiiKind.card;
    if (email.contains(t)) return PiiKind.email;
    if (phone.contains(t)) return PiiKind.phone;
  }
  return null;
}

String _refMask(PiiKind kind, String value) {
  if (value.isEmpty || value == 'NULL') return value;
  switch (kind) {
    case PiiKind.secret:
      return kPiiMaskDots;
    case PiiKind.email:
      final at = value.indexOf('@');
      if (at <= 0 || at == value.length - 1) return kPiiMaskDots;
      final local = value.substring(0, at);
      final domain = value.substring(at + 1);
      final visible = local.length <= 2 ? 1 : 2;
      return '${local.substring(0, visible)}***@$domain';
    case PiiKind.phone:
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8) return kPiiMaskDots;
      return '•••••••${digits.substring(digits.length - 2)}';
    case PiiKind.card:
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 12) return kPiiMaskDots;
      return '•••• •••• •••• ${digits.substring(digits.length - 4)}';
  }
}

void main() {
  group('PII column detection scanner (#1540)', () {
    test('agrees with the previous implementation on listed names', () {
      const names = <String>[
        '', ' ', '_', 'id', 'name', 'password', 'PASSWORD_HASH', 'auth_token',
        'api_key', 'apiKey', 'API_KEY', 'APIKey', 'api2Key', 'private_key',
        'accessKey', 'secret_key_id', 'my_api_key_2', 'monkey', 'key',
        'clientSecret', 'email', 'userEmail', 'contact_email', 'EMAIL',
        'email_verified_at', 'phone', 'mobile_number', 'phoneNumber2',
        'card_number', 'credit_card', 'cardId', 'card_id', 'CreditCardNumber',
        'hotel', 'compass', 'cardinality', 'telegram_handle', 'created_at',
        'user.email', 'users.email', '"email"', 'e-mail', 'Email Address',
        'ÉMAIL', 'телефон', 'tel', 'msisdn_2', 'iban', 'IBAN_code', 'pan',
      ];
      for (final n in names) {
        expect(detectPiiColumn(n), _refDetect(n), reason: '"$n"');
        // The second call is served from the cache.
        expect(detectPiiColumn(n), _refDetect(n), reason: 'cached "$n"');
      }
    });

    test('agrees with the previous implementation on random names', () {
      const parts = <String>[
        'api', 'key', 'Key', 'KEY', 'user', 'User', 'email', 'Email', 'phone',
        'card', 'Card', 'id', 'at', 'count', 'secret', 'token', 'x', 'A', '1',
        '_', '-', '.', ' ', 'é',
      ];
      final random = Random(1540);
      for (var n = 0; n < 4000; n++) {
        final name = [
          for (var k = 1 + random.nextInt(5); k > 0; k--)
            parts[random.nextInt(parts.length)],
        ].join();
        expect(detectPiiColumn(name), _refDetect(name), reason: '"$name"');
      }
    });

    test('more distinct names than the cache holds still answer correctly', () {
      for (var i = 0; i < 2500; i++) {
        expect(detectPiiColumn('col_$i'), isNull);
      }
      expect(detectPiiColumn('user_email'), PiiKind.email);
      expect(detectPiiColumn('user_email'), PiiKind.email);
    });
  });

  group('PII value masking scanner (#1516)', () {
    test('agrees with the previous implementation', () {
      const values = <String>[
        '', 'NULL', 'null', 'abc', '1234567', '12345678', '+1 (555) 123-4567',
        '555.123.4567 ext 89', '4111 1111 1111 1111', '4111-1111-1111-111',
        '41111111111', '411111111111', 'DE89 3704 0044 0532 0130 00',
        '٠١٢٣٤٥٦٧٨٩٠١٢', '１２３４５６７８９０１２', 'a@b.c', 'ab@x.org',
        'alice@example.com', '@x', 'x@',
      ];
      for (final kind in PiiKind.values) {
        for (final v in values) {
          expect(maskPiiValue(kind, v), _refMask(kind, v),
              reason: '$kind "$v"');
        }
      }
    });

    test('agrees with the previous implementation on random digit soup', () {
      const pieces = <String>[
        '0', '1', '7', '9', ' ', '-', '(', ')', '+', '.', 'x', 'é', '٣',
      ];
      final random = Random(1516);
      for (var n = 0; n < 3000; n++) {
        final v = [
          for (var k = random.nextInt(24); k > 0; k--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        for (final kind in [PiiKind.phone, PiiKind.card]) {
          expect(maskPiiValue(kind, v), _refMask(kind, v),
              reason: '$kind "$v"');
        }
      }
    });
  });
}
