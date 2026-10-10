import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';

void main() {
  group('redactUriPassword', () {
    test('strips password from userinfo', () {
      expect(
        redactUriPassword('postgresql://alice:s3cret@db.example:5432/app'),
        'postgresql://alice@db.example:5432/app',
      );
    });

    test('leaves uri without password unchanged', () {
      const uri = 'postgresql://alice@db.example:5432/app';
      expect(redactUriPassword(uri), uri);
    });
  });

  group('injectUriPasswordIfMissing', () {
    test('injects password when user has no password', () {
      expect(
        injectUriPasswordIfMissing(
          'postgresql://alice@db.example:5432/app',
          's3cret',
        ),
        'postgresql://alice:s3cret@db.example:5432/app',
      );
    });

    test('percent-encodes a password with URI special characters', () {
      // A raw `@` or `/` made Uri.replace throw a FormatException on Save.
      final uri = injectUriPasswordIfMissing(
        'postgresql://alice@db.example:5432/app',
        'p@ss/w#rd',
      );
      expect(uri, 'postgresql://alice:p%40ss%2Fw%23rd@db.example:5432/app');
      final parsed = Uri.parse(uri);
      expect(parsed.host, 'db.example');
      expect(
          Uri.decodeComponent(parsed.userInfo.split(':').last), 'p@ss/w#rd');
    });

    test('keeps existing password', () {
      const uri = 'postgresql://alice:keep@db.example:5432/app';
      expect(injectUriPasswordIfMissing(uri, 'other'), uri);
    });
  });

  group('ConnectionRow.copyWith', () {
    test('can clear password with flag', () {
      const row = ConnectionRow(
        id: 1,
        type: 'postgresql',
        name: 'n',
        password: 'x',
        createdAt: 't',
      );
      expect(row.copyWith(clearPassword: true).password, isNull);
      expect(row.copyWith(password: 'y').password, 'y');
    });
  });
}
