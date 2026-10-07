import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/security/safe_mode.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

ConnectionRow _row({String? driverOptions, String name = 'orders-prod'}) =>
    ConnectionRow(
      id: 1,
      type: 'postgresql',
      name: name,
      host: 'db.example.com',
      port: 5432,
      driverOptions: driverOptions,
      createdAt: DateTime.utc(2026).toIso8601String(),
    );

void main() {
  group('ConnectionEnvironment', () {
    test('only production defaults to read-only', () {
      expect(ConnectionEnvironment.production.defaultsToReadOnly, isTrue);
      expect(ConnectionEnvironment.staging.defaultsToReadOnly, isFalse);
      expect(ConnectionEnvironment.development.defaultsToReadOnly, isFalse);
    });

    test('badges and labels', () {
      expect(ConnectionEnvironment.production.badge, 'PROD');
      expect(ConnectionEnvironment.staging.badge, 'STAGING');
      expect(ConnectionEnvironment.development.badge, 'DEV');
      expect(ConnectionEnvironment.production.label, 'Production');
    });

    test('reads the tag from driver options', () {
      expect(
        ConnectionEnvironment.fromDriverOptions(
            '{"querya_environment":"staging"}'),
        ConnectionEnvironment.staging,
      );
    });

    test('untagged, malformed and unknown values read as null', () {
      expect(ConnectionEnvironment.fromDriverOptions(null), isNull);
      expect(ConnectionEnvironment.fromDriverOptions(''), isNull);
      expect(ConnectionEnvironment.fromDriverOptions('{nope'), isNull);
      expect(ConnectionEnvironment.fromDriverOptions('[1]'), isNull);
      expect(
        ConnectionEnvironment.fromDriverOptions(
            '{"querya_environment":"qa"}'),
        isNull,
      );
    });

    test('applying keeps unrelated options', () {
      final out = ConnectionEnvironment.applyToDriverOptions(
        '{"ssh_tunnel":{"host":"bastion"},"cluster":"eu"}',
        ConnectionEnvironment.production,
      );
      final decoded = jsonDecode(out!) as Map<String, dynamic>;
      expect(decoded['querya_environment'], 'production');
      expect(decoded['cluster'], 'eu');
      expect(decoded['ssh_tunnel'], {'host': 'bastion'});
    });

    test('removing the only key yields null', () {
      expect(
        ConnectionEnvironment.applyToDriverOptions(
          '{"querya_environment":"production"}',
          null,
        ),
        isNull,
      );
    });
  });

  group('ConnectionRow environment', () {
    test('is null for an untagged connection', () {
      expect(_row().environment, isNull);
    });

    test('withEnvironment tags and untags, preserving other options', () {
      final tagged = _row(driverOptions: '{"cluster":"eu"}')
          .withEnvironment(ConnectionEnvironment.production);
      expect(tagged.environment, ConnectionEnvironment.production);
      expect(jsonDecode(tagged.driverOptions!)['cluster'], 'eu');

      final untagged = tagged.withEnvironment(null);
      expect(untagged.environment, isNull);
      expect(jsonDecode(untagged.driverOptions!), {'cluster': 'eu'});
    });

    test('untagging a row with no other options clears driverOptions', () {
      final row = _row()
          .withEnvironment(ConnectionEnvironment.staging)
          .withEnvironment(null);
      expect(row.driverOptions, isNull);
    });

    test('survives the database map round trip', () {
      final row = _row().withEnvironment(ConnectionEnvironment.production);
      final restored = ConnectionRow.fromMap(row.toMap());
      expect(restored.environment, ConnectionEnvironment.production);
    });

    test('is independent of the SSH tunnel option', () {
      final row = _row()
          .withEnvironment(ConnectionEnvironment.production)
          .withSshTunnelConfig(null);
      expect(row.environment, ConnectionEnvironment.production);
    });
  });

  group('Safe Mode', () {
    test('only production needs a typed confirmation', () {
      expect(safeModeRequiresConfirmation(ConnectionEnvironment.production),
          isTrue);
      expect(
          safeModeRequiresConfirmation(ConnectionEnvironment.staging), isFalse);
      expect(safeModeRequiresConfirmation(null), isFalse);
    });

    test('the confirmation phrase is the connection name', () {
      expect(safeModeConfirmationPhrase(' orders-prod '), 'orders-prod');
      expect(safeModeConfirmationPhrase('  '), 'PRODUCTION');
    });

    test('confirmation must match exactly, ignoring surrounding spaces', () {
      expect(isSafeModeConfirmationValid(' orders-prod ', 'orders-prod'),
          isTrue);
      expect(isSafeModeConfirmationValid('Orders-Prod', 'orders-prod'),
          isFalse);
      expect(isSafeModeConfirmationValid('', 'orders-prod'), isFalse);
    });

    test('unlock lasts five minutes', () {
      expect(kSafeModeUnlockDuration, const Duration(minutes: 5));
    });
  });
}
