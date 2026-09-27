import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../memory_secrets_backend.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;

  @override
  Future<String?> getApplicationCachePath() async => _root;

  @override
  Future<String?> getLibraryPath() async => _root;

  @override
  Future<String?> getExternalStoragePath() async => _root;

  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];

  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [_root];

  @override
  Future<String?> getDownloadsPath() async => _root;
}

/// Regression tests for issue #986: two independent profile databases (each
/// with its own `connections` autoincrement sequence starting at 1) must not
/// collide in the shared OS keyring when they mint the same connection id.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory rootA;
  late Directory rootB;

  setUp(() async {
    rootA = await Directory.systemTemp.createTemp('querya_profile_a_');
    rootB = await Directory.systemTemp.createTemp('querya_profile_b_');
    await LocalDb.initFfi();
  });

  tearDown(() async {
    await LocalDb.instance.close();
    ConnectionSecretsStore.profileId = null;
    testMemorySecrets.clear();
    if (await rootA.exists()) await rootA.delete(recursive: true);
    if (await rootB.exists()) await rootB.delete(recursive: true);
  });

  test(
      'two profile databases with the same connection id keep independent secrets',
      () async {
    // Profile A mints connection id 1 with a password.
    PathProviderPlatform.instance = _FakePathProvider(rootA.path);
    final idA = await LocalDb.instance.addConnection(const ConnectionRow(
      type: 'postgres',
      name: 'A1',
      host: 'a-host',
      port: 5432,
      password: 'profile-a-secret',
      createdAt: '2026-01-01T00:00:00Z',
    ));
    expect(idA, 1);
    final profileIdA = ConnectionSecretsStore.profileId;
    expect(profileIdA, isNotNull);

    await LocalDb.instance.close();
    ConnectionSecretsStore.profileId = null;

    // Profile B is a separate database that also mints connection id 1, but
    // without a password. Saving it must not touch profile A's secret.
    PathProviderPlatform.instance = _FakePathProvider(rootB.path);
    final idB = await LocalDb.instance.addConnection(const ConnectionRow(
      type: 'postgres',
      name: 'B1',
      host: 'b-host',
      port: 5432,
      createdAt: '2026-01-01T00:00:00Z',
    ));
    expect(idB, 1);
    final profileIdB = ConnectionSecretsStore.profileId;
    expect(profileIdB, isNotNull);
    expect(profileIdB, isNot(profileIdA));

    final loadedB =
        (await LocalDb.instance.getConnections(hydrateSecrets: true)).single;
    expect(loadedB.password, isNull);

    await LocalDb.instance.close();
    ConnectionSecretsStore.profileId = null;

    // Back in profile A, connection 1's password must still be intact.
    PathProviderPlatform.instance = _FakePathProvider(rootA.path);
    final loadedA =
        (await LocalDb.instance.getConnections(hydrateSecrets: true)).single;
    expect(loadedA.id, 1);
    expect(loadedA.password, 'profile-a-secret');
  });

  test('adoptLegacyKeysForConnection migrates a pre-#986 unnamespaced secret',
      () async {
    PathProviderPlatform.instance = _FakePathProvider(rootA.path);
    final id = await LocalDb.instance.addConnection(const ConnectionRow(
      type: 'redis',
      name: 'Legacy',
      host: 'legacy-host',
      port: 6379,
      createdAt: '2026-01-01T00:00:00Z',
    ));
    final profileId = ConnectionSecretsStore.profileId!;

    // Simulate a pre-#986 install: write directly under the old unnamespaced
    // key format instead of the namespaced one.
    await testMemorySecrets.write('querya.v1.conn.$id.password', 'legacy-pw');

    await ConnectionSecretsStore.adoptLegacyKeysForConnection(id);

    final secrets = await ConnectionSecretsStore.readForConnection(id);
    expect(secrets.password, 'legacy-pw');
    expect(await testMemorySecrets.read('querya.v1.conn.$id.password'), isNull);
    expect(ConnectionSecretsStore.profileId, profileId);
  });

  test(
      'readForConnection lazily adopts legacy unnamespaced secret on demand (#1008)',
      () async {
    PathProviderPlatform.instance = _FakePathProvider(rootA.path);
    final id = await LocalDb.instance.addConnection(const ConnectionRow(
      type: 'postgres',
      name: 'UnmigratedLegacy',
      host: 'legacy-pg-host',
      port: 5432,
      createdAt: '2026-01-01T00:00:00Z',
    ));
    final profileId = ConnectionSecretsStore.profileId!;

    // Simulate an unmigrated secret (e.g. transient keyring lock during DB upgrade):
    // only the legacy unnamespaced keys exist.
    await testMemorySecrets.write('querya.v1.conn.$id.password', 'lazy-pw');
    await testMemorySecrets.write(
        'querya.v1.conn.$id.connection_string', 'postgres://user:lazy-pw@host/db');

    // Neither adoptLegacyKeysForConnection nor writeForConnection was called.
    // readForConnection must fall back to the legacy keys, adopt them write-through,
    // and return the credentials.
    final secrets = await ConnectionSecretsStore.readForConnection(id);
    expect(secrets.password, 'lazy-pw');
    expect(secrets.connectionString, 'postgres://user:lazy-pw@host/db');

    // The legacy keys should now be cleaned up, and namespaced keys populated.
    expect(await testMemorySecrets.read('querya.v1.conn.$id.password'), isNull);
    expect(await testMemorySecrets.read('querya.v1.conn.$id.connection_string'),
        isNull);
    expect(
      await testMemorySecrets.read(
          'querya.v1.profile.$profileId.conn.$id.password'),
      'lazy-pw',
    );
    expect(
      await testMemorySecrets.read(
          'querya.v1.profile.$profileId.conn.$id.connection_string'),
      'postgres://user:lazy-pw@host/db',
    );
  });

  test('deleteForConnection removes both namespaced and legacy keys (#1008)',
      () async {
    PathProviderPlatform.instance = _FakePathProvider(rootA.path);
    final id = await LocalDb.instance.addConnection(const ConnectionRow(
      type: 'postgres',
      name: 'ToDelete',
      host: 'host',
      port: 5432,
      createdAt: '2026-01-01T00:00:00Z',
    ));
    final profileId = ConnectionSecretsStore.profileId!;

    await testMemorySecrets.write(
        'querya.v1.profile.$profileId.conn.$id.password', 'pw');
    await testMemorySecrets.write(
        'querya.v1.conn.$id.password', 'stray-legacy-pw');

    await ConnectionSecretsStore.deleteForConnection(id);

    expect(
      await testMemorySecrets.read(
          'querya.v1.profile.$profileId.conn.$id.password'),
      isNull,
    );
    expect(await testMemorySecrets.read('querya.v1.conn.$id.password'), isNull);
  });
}
