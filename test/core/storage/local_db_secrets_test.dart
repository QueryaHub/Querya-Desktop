import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_local_db_secrets_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    testMemorySecrets.clear();
    for (final c in await LocalDb.instance.getConnections()) {
      if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
    }
  });

  group('LocalDb secrets', () {
    test('addConnection leaves password out of SQLite', () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R1',
        host: '127.0.0.1',
        port: 6379,
        password: 'redis-secret',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      final dbFile = p.join(tempDir.path, 'querya_desktop', 'querya.db');
      await LocalDb.instance.close();
      sqfliteFfiInit();
      final raw = await databaseFactoryFfi.openDatabase(
        dbFile,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final maps =
            await raw.query('connections', where: 'id = ?', whereArgs: [id]);
        expect(maps.single['password'], isNull);
      } finally {
        await raw.close();
      }

      final list = await LocalDb.instance.getConnections();
      final loaded = list.singleWhere((c) => c.id == id);
      // Secrets are resolved lazily on demand, not eagerly in getConnections()
      expect(loaded.password, isNull);

      final hydrated = await LocalDb.instance.hydrateConnection(loaded);
      expect(hydrated.password, 'redis-secret');

      final eagerlyHydrated = (await LocalDb.instance.getConnections(hydrateSecrets: true))
          .singleWhere((c) => c.id == id);
      expect(eagerlyHydrated.password, 'redis-secret');
    });

    test('removeConnection deletes secure-store entries', () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R2',
        host: '127.0.0.1',
        port: 6379,
        password: 'x',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      await LocalDb.instance.removeConnection(id);

      final s = await ConnectionSecretsStore.readForConnection(id);
      expect(s.password, isNull);
      expect(s.connectionString, isNull);
    });

    test(
        'updateConnection atomically updates SQLite row and secure-store secrets',
        () async {
      const initialRow = ConnectionRow(
        type: 'postgres',
        name: 'PG_Init',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'old-secret-password',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      final updatedRow = ConnectionRow(
        id: id,
        type: 'postgres',
        name: 'PG_Updated',
        host: 'db.example.com',
        port: 5433,
        username: 'root',
        password: 'new-secret-password',
        connectionString:
            'postgres://root:new-secret-password@db.example.com:5433/mydb',
        createdAt: '2026-01-01T00:00:00Z',
      );
      await LocalDb.instance.updateConnection(updatedRow);

      final list = await LocalDb.instance.getConnections(hydrateSecrets: true);
      final loaded = list.singleWhere((c) => c.id == id);
      expect(loaded.name, 'PG_Updated');
      expect(loaded.host, 'db.example.com');
      expect(loaded.port, 5433);
      expect(loaded.username, 'root');
      expect(loaded.password, 'new-secret-password');
      expect(loaded.connectionString,
          'postgres://root:new-secret-password@db.example.com:5433/mydb');

      final secrets = await ConnectionSecretsStore.readForConnection(id);
      expect(secrets.password, 'new-secret-password');
      expect(secrets.connectionString,
          'postgres://root:new-secret-password@db.example.com:5433/mydb');
    });

    test(
        'removeConnection still deletes SQLite row when secure-store delete fails',
        () async {
      const row = ConnectionRow(
        type: 'redis',
        name: 'R3',
        host: '127.0.0.1',
        port: 6379,
        password: 'x',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      testMemorySecrets.failNextDelete = StateError('libsecret unavailable');

      await LocalDb.instance.removeConnection(id);

      final list = await LocalDb.instance.getConnections();
      expect(list.where((c) => c.id == id), isEmpty);
    });

    test('addConnection rolls back SQLite row when secure-store write fails',
        () async {
      testMemorySecrets.failNextWrite = StateError('keychain write failed');
      const row = ConnectionRow(
        type: 'redis',
        name: 'R4',
        host: '127.0.0.1',
        port: 6379,
        password: 'secret',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await expectLater(
        LocalDb.instance.addConnection(row),
        throwsA(isA<StateError>()),
      );

      final list = await LocalDb.instance.getConnections();
      expect(list.where((c) => c.name == 'R4'), isEmpty);
    });

    test(
        'updateConnection rolls back SQLite and secrets when secure-store write fails',
        () async {
      const initialRow = ConnectionRow(
        type: 'postgres',
        name: 'PG_Before',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'old-password',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      testMemorySecrets.failNextWrite = StateError('keychain write failed');
      final updatedRow = ConnectionRow(
        id: id,
        type: 'postgres',
        name: 'PG_After',
        host: 'db.example.com',
        port: 5433,
        username: 'root',
        password: 'new-password',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await expectLater(
        LocalDb.instance.updateConnection(updatedRow),
        throwsA(isA<StateError>()),
      );

      final list = await LocalDb.instance.getConnections(hydrateSecrets: true);
      final loaded = list.singleWhere((c) => c.id == id);
      expect(loaded.name, 'PG_Before');
      expect(loaded.host, 'localhost');
      expect(loaded.port, 5432);
      expect(loaded.username, 'admin');
      expect(loaded.password, 'old-password');
    });

    test(
        'mergeSecretsForConnectionUpdate keeps password when form leaves it blank',
        () async {
      const initialRow = ConnectionRow(
        type: 'postgresql',
        name: 'PG',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'keep-me',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      final edited = ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'PG Renamed',
        host: 'db.example.com',
        port: 5432,
        username: 'admin',
        password: null,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final merged = await mergeSecretsForConnectionUpdate(edited);
      expect(merged.password, 'keep-me');
      expect(merged.name, 'PG Renamed');
      expect(merged.host, 'db.example.com');

      await LocalDb.instance.updateConnection(merged);
      final loaded = (await LocalDb.instance.getConnections(hydrateSecrets: true))
          .singleWhere((c) => c.id == id);
      expect(loaded.password, 'keep-me');
      expect(loaded.name, 'PG Renamed');
    });

    test(
        'SSH secrets are saved to secure store and merged during update',
        () async {
      final initialRow = ConnectionRow(
        type: 'postgresql',
        name: 'PG with SSH',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'db-password',
        createdAt: '2026-01-01T00:00:00Z',
        sshSecrets: SshTunnelSecrets(
          password: 'ssh-pass-123',
          privateKey: 'ssh-key-data',
          passphrase: 'key-passphrase',
        ),
      );
      final id = await LocalDb.instance.addConnection(initialRow);

      final readSsh =
          await ConnectionSecretsStore.readSshSecretsForConnection(id);
      expect(readSsh.password, 'ssh-pass-123');
      expect(readSsh.privateKey, 'ssh-key-data');
      expect(readSsh.passphrase, 'key-passphrase');

      // Edit connection without re-entering SSH secrets (empty/blank)
      final edited = ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'PG with SSH Renamed',
        createdAt: '2026-01-01T00:00:00Z',
        sshSecrets: SshTunnelSecrets(),
      );

      final merged = await mergeSecretsForConnectionUpdate(edited);
      expect(merged.sshSecrets?.password, 'ssh-pass-123');
      expect(merged.sshSecrets?.privateKey, 'ssh-key-data');
      expect(merged.sshSecrets?.passphrase, 'key-passphrase');

      await LocalDb.instance.updateConnection(merged);
      final afterUpdate =
          await ConnectionSecretsStore.readSshSecretsForConnection(id);
      expect(afterUpdate.password, 'ssh-pass-123');
      expect(afterUpdate.privateKey, 'ssh-key-data');

      // Deleting connection also deletes SSH secrets
      await LocalDb.instance.removeConnection(id);
      final afterDelete =
          await ConnectionSecretsStore.readSshSecretsForConnection(id);
      expect(afterDelete.password, isNull);
      expect(afterDelete.privateKey, isNull);
    });

    test('getConnections does not read secure store by default', () async {
      const row = ConnectionRow(
        type: 'mysql',
        name: 'MySQL_Lazy',
        host: 'localhost',
        port: 3306,
        username: 'root',
        password: 'super-secret-pw',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      // failNextRead should NOT be triggered because getConnections() does not read secrets!
      testMemorySecrets.failNextRead = StateError('should not be called');

      final list = await LocalDb.instance.getConnections();
      final conn = list.singleWhere((c) => c.id == id);
      expect(conn.name, 'MySQL_Lazy');
      expect(conn.password, isNull);

      // failNextRead is still set because read was never called
      expect(testMemorySecrets.failNextRead, isNotNull);
      testMemorySecrets.failNextRead = null;
    });

    test(
        'a store that cannot be read throws, and hydrating a list survives it',
        () async {
      const row = ConnectionRow(
        type: 'mysql',
        name: 'MySQL_Faulty',
        host: 'localhost',
        port: 3306,
        username: 'root',
        password: 'secret-password',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);

      testMemorySecrets.failNextRead =
          Exception('org.freedesktop.DBus.Error.NoReply');

      // Not "no password": the caller must be able to tell (#1303).
      await expectLater(ConnectionSecretsStore.readForConnection(id),
          throwsA(isA<SecretsStoreUnavailableException>()));

      testMemorySecrets.failNextRead = Exception('Keychain locked');
      await expectLater(ConnectionSecretsStore.readSshSecretsForConnection(id),
          throwsA(isA<SecretsStoreUnavailableException>()));

      // A list still loads: that row is just without its password.
      testMemorySecrets.failNextRead = Exception('Keychain locked');
      final list = await LocalDb.instance.getConnections(hydrateSecrets: true);
      final conn = list.singleWhere((c) => c.id == id);
      expect(conn.name, 'MySQL_Faulty');
      expect(conn.password, isNull);

      // And the secret is still there once the store answers again.
      final secrets = await ConnectionSecretsStore.readForConnection(id);
      expect(secrets.password, 'secret-password');
    });

    test('an absent secret reads as null, not as an error', () async {
      final secrets = await ConnectionSecretsStore.readForConnection(987654);
      expect(secrets.password, isNull);
      expect(secrets.connectionString, isNull);
      final ssh = await ConnectionSecretsStore.readSshSecretsForConnection(
          987654);
      expect(ssh.password, isNull);
    });

    test(
        'an edit while the store cannot be read changes nothing and keeps '
        'the saved password', () async {
      const row = ConnectionRow(
        type: 'postgresql',
        name: 'Before',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'keep-me',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      final edited = ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'After',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        createdAt: '2026-01-01T00:00:00Z',
      );

      // The merge reads the saved password first and stops there.
      testMemorySecrets.failNextRead = Exception('Keychain locked');
      await expectLater(mergeSecretsForConnectionUpdate(edited),
          throwsA(isA<SecretsStoreUnavailableException>()));

      // Writing the unmerged row would erase it: updateConnection refuses to
      // run on a store it cannot read.
      testMemorySecrets.failNextRead = Exception('Keychain locked');
      await expectLater(LocalDb.instance.updateConnection(edited),
          throwsA(isA<SecretsStoreUnavailableException>()));

      final loaded = (await LocalDb.instance.getConnections(hydrateSecrets: true))
          .singleWhere((c) => c.id == id);
      expect(loaded.name, 'Before');
      expect(loaded.password, 'keep-me');
    });

    test('Remove the saved password removes it; a typed one replaces it',
        () async {
      const row = ConnectionRow(
        type: 'postgresql',
        name: 'PG',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'old-secret',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      ConnectionRow edit({String? password, bool remove = false}) =>
          ConnectionRow(
            id: id,
            type: 'postgresql',
            name: 'PG',
            host: 'localhost',
            port: 5432,
            username: 'admin',
            password: password,
            createdAt: '2026-01-01T00:00:00Z',
            removeSavedPassword: remove,
          );

      // Blank keeps it (as before) ...
      var merged = await mergeSecretsForConnectionUpdate(edit());
      expect(merged.password, 'old-secret');

      // ... unless removal was asked for.
      merged = await mergeSecretsForConnectionUpdate(edit(remove: true));
      expect(merged.password, isNull);
      await LocalDb.instance.updateConnection(merged);
      expect((await ConnectionSecretsStore.readForConnection(id)).password,
          isNull);

      // A password typed with the request replaces: nothing is lost by it.
      merged = await mergeSecretsForConnectionUpdate(
          edit(password: 'new-secret', remove: true));
      expect(merged.password, 'new-secret');
    });

    test('turning the SSH tunnel off removes its secrets from the store',
        () async {
      final withTunnel = ConnectionRow(
        type: 'postgresql',
        name: 'PG via bastion',
        host: 'db.internal',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
        sshSecrets: SshTunnelSecrets(
          password: 'ssh-pass',
          privateKey: 'ssh-key',
          passphrase: 'phrase',
          jumpPassword: 'jump',
        ),
      ).withSshTunnelConfig(const SshTunnelConfig(
        enabled: true,
        host: 'bastion.example',
        port: 22,
        username: 'deploy',
      ));
      final id = await LocalDb.instance.addConnection(withTunnel);
      expect(
          (await ConnectionSecretsStore.readSshSecretsForConnection(id))
              .privateKey,
          'ssh-key');

      // The form saves without a tunnel and without SSH secrets.
      final off = ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'PG via bastion',
        host: 'db.internal',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
      ).withSshTunnelConfig(null);
      await LocalDb.instance.updateConnection(
          await mergeSecretsForConnectionUpdate(off));

      final left = await ConnectionSecretsStore.readSshSecretsForConnection(id);
      expect(left.password, isNull);
      expect(left.privateKey, isNull);
      expect(left.passphrase, isNull);
      expect(left.jumpPassword, isNull);
    });

    test('a failed update restores the SSH secrets as well', () async {
      const tunnel = SshTunnelConfig(
        enabled: true,
        host: 'bastion.example',
        port: 22,
        username: 'deploy',
      );
      final id = await LocalDb.instance.addConnection(ConnectionRow(
        type: 'postgresql',
        name: 'PG',
        host: 'db.internal',
        port: 5432,
        password: 'db-pass',
        createdAt: '2026-01-01T00:00:00Z',
        sshSecrets:
            SshTunnelSecrets(password: 'ssh-old', privateKey: 'key-old'),
      ).withSshTunnelConfig(tunnel));

      // Writes of the update: password, connection string, then the four SSH
      // keys: the fourth write (the private key) fails.
      final real = ConnectionSecretsStore.backend;
      ConnectionSecretsStore.backend = _FailsOnWrite(real, failOn: 4);
      addTearDown(() => ConnectionSecretsStore.backend = real);

      await expectLater(
        LocalDb.instance.updateConnection(ConnectionRow(
          id: id,
          type: 'postgresql',
          name: 'PG',
          host: 'db.internal',
          port: 5432,
          password: 'db-pass',
          createdAt: '2026-01-01T00:00:00Z',
          sshSecrets:
              SshTunnelSecrets(password: 'ssh-new', privateKey: 'key-new'),
        ).withSshTunnelConfig(tunnel)),
        throwsA(isA<StateError>()),
      );
      ConnectionSecretsStore.backend = real;

      final ssh = await ConnectionSecretsStore.readSshSecretsForConnection(id);
      expect(ssh.password, 'ssh-old');
      expect(ssh.privateKey, 'key-old');
      expect((await ConnectionSecretsStore.readForConnection(id)).password,
          'db-pass');
    });
  });
}

/// A backend whose [failOn]th write (1-based, counted from the first write
/// through it) throws; every other call goes to [inner].
class _FailsOnWrite implements SecretsStorageBackend {
  _FailsOnWrite(this.inner, {required this.failOn});

  final SecretsStorageBackend inner;
  final int failOn;
  int _writes = 0;

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String? value) async {
    if (++_writes == failOn) throw StateError('keyring write failed');
    await inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => inner.delete(key);
}
