import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../memory_secrets_backend.dart';
import '../helpers/e2e_app_harness.dart';

const _password = 'Zx9-unique-secret-PW';
const _url = 'postgresql://alice:Zx9-unique-secret-PW@db.example.com/app';

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_secrets_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  test('passwords go to the secure store and never into querya.db', () async {
    final id = await LocalDb.instance.addConnection(ConnectionRow(
      type: 'postgresql',
      name: 'Secret PG',
      host: 'db.example.com',
      port: 5432,
      username: 'alice',
      password: _password,
      connectionString: _url,
      createdAt: DateTime.utc(2026).toIso8601String(),
    ));

    // Secure store holds the secrets.
    final secrets = await ConnectionSecretsStore.readForConnection(id);
    expect(secrets.password, _password);
    expect(secrets.connectionString, _url);

    // The sidebar read path (no hydration) exposes no secret.
    final listed = (await LocalDb.instance.getConnections()).single;
    expect(listed.password, anyOf(isNull, isEmpty));
    expect(listed.connectionString, anyOf(isNull, isEmpty));

    // No database file under the data directory contains the secret.
    await LocalDb.instance.close();
    final files = app.dataDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('.db'));
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(String.fromCharCodes(f.readAsBytesSync()), isNot(contains(_password)),
          reason: f.path);
    }
  });

  test('removing a connection erases its secrets', () async {
    final id = await LocalDb.instance.addConnection(ConnectionRow(
      type: 'redis',
      name: 'Secret Redis',
      host: 'cache',
      port: 6379,
      password: _password,
      createdAt: DateTime.utc(2026).toIso8601String(),
    ));
    expect((await ConnectionSecretsStore.readForConnection(id)).password,
        _password);
    await LocalDb.instance.removeConnection(id);
    expect((await ConnectionSecretsStore.readForConnection(id)).password,
        isNull);
    expect(testMemorySecrets, isNotNull);
  });
}
