import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

import '../../memory_secrets_backend.dart';

/// #1303: a keyring that cannot be read is not "no password".
void main() {
  setUp(() {
    ConnectionSecretsStore.profileId = 'test-profile';
    testMemorySecrets.clear();
  });

  final unreadable = isA<SecretsStoreUnavailableException>();

  group('connect with a saved connection whose secrets cannot be read', () {
    test('PostgreSQL', () async {
      final c = PostgresConnection(
          id: 3, name: 'pg', host: 'localhost', port: 5432);
      testMemorySecrets.failNextRead = Exception('keyring is locked');
      await expectLater(c.connect(), throwsA(unreadable));
      expect(c.isConnected, isFalse);
    });

    test('MySQL', () async {
      final c = MysqlConnection(
          id: 3, name: 'my', host: 'localhost', port: 3306);
      testMemorySecrets.failNextRead = Exception('keyring is locked');
      await expectLater(c.connect(), throwsA(unreadable));
    });

    test('Redis', () async {
      final c = RedisConnection(id: 3, name: 'r', host: 'localhost');
      testMemorySecrets.failNextRead = Exception('keyring is locked');
      await expectLater(c.connect(), throwsA(unreadable));
    });

    test('MongoDB', () async {
      final c = MongoConnection(
          id: 3, name: 'mo', host: 'localhost', port: 27017);
      testMemorySecrets.failNextRead = Exception('keyring is locked');
      await expectLater(c.connect(), throwsA(unreadable));
    });
  });

  group('mapDatabaseError', () {
    test('an unreadable store is not an authentication failure', () {
      // Even when the platform's own text sounds like one.
      final mapped = mapDatabaseError(SecretsStoreUnavailableException(
          Exception('libsecret: authentication failed')));
      expect(mapped, isNot(isA<AuthFailedException>()));
      expect(mapped.message, contains('system keyring'));
      expect(mapped.remediationHint, contains('Unlock the keyring'));
    });

    test('its one-line text names the keyring, not the credentials', () {
      final text = describeDatabaseError(SecretsStoreUnavailableException(
          Exception('The collection is locked')));
      expect(text, contains('keyring'));
      expect(text.toLowerCase(), isNot(contains('check the username')));
    });
  });
}
