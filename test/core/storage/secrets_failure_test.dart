import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
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
}

/// What the app does when the system keyring refuses a request part-way
/// through a save or a read: the write path is all-or-nothing as far as the
/// stored connection goes (the row and its secrets are rolled back, the
/// original error is rethrown), and the read path tells "could not read" from
/// "no secret" (#1303). Faults are aimed with the numbered calls of
/// `memory_secrets_backend.dart`: a connection's secrets are written one key
/// after another (password, connection string, then the four SSH keys).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_secrets_fail_');
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
    testMemorySecrets.clear();
  });

  ConnectionRow row(String name, {SshTunnelSecrets? ssh}) => ConnectionRow(
        type: 'postgresql',
        name: name,
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'db-password',
        connectionString: 'postgres://admin@localhost/db',
        createdAt: '2026-01-01T00:00:00Z',
        sshSecrets: ssh,
      );

  Future<List<ConnectionRow>> rowsNamed(String name) async =>
      (await LocalDb.instance.getConnections())
          .where((c) => c.name == name)
          .toList();

  group('a write that fails part-way', () {
    test(
        'addConnection: the first secret is stored, the second is refused: '
        'no row, no secret left, the original error comes out', () async {
      final error = StateError('connection string refused');
      testMemorySecrets.failOnCall(SecretsOp.write, 2, error);

      await expectLater(
        LocalDb.instance.addConnection(row('Partial add')),
        throwsA(same(error)),
      );

      expect(testMemorySecrets.writeCalls, 2);
      expect(await rowsNamed('Partial add'), isEmpty);
      expect(testMemorySecrets.keys, isEmpty,
          reason: 'the password written before the refusal must not stay');
    });

    test('addConnection: a refusal among the SSH secrets rolls back them all',
        () async {
      // Writes: password 1, connection string 2, SSH password 3, SSH key 4.
      final error = StateError('ssh key refused');
      testMemorySecrets.failOnCall(SecretsOp.write, 4, error);

      await expectLater(
        LocalDb.instance.addConnection(row(
          'Partial ssh',
          ssh: SshTunnelSecrets(password: 'ssh-pw', privateKey: 'ssh-key'),
        )),
        throwsA(same(error)),
      );

      expect(await rowsNamed('Partial ssh'), isEmpty);
      expect(testMemorySecrets.keys, isEmpty);
    });

    test(
        'addConnection: when the cleanup is refused as well the row is still '
        'removed and the first error is the one reported', () async {
      final error = StateError('write refused');
      testMemorySecrets.failOnCall(SecretsOp.write, 2, error);
      testMemorySecrets.failAlways(SecretsOp.delete, StateError('no delete'));

      await expectLater(
        LocalDb.instance.addConnection(row('Stuck cleanup')),
        throwsA(same(error)),
      );

      expect(await rowsNamed('Stuck cleanup'), isEmpty);
    });

    test(
        'updateConnection: a refusal after the new password was stored puts '
        'back the old row and both old secrets', () async {
      final id = await LocalDb.instance.addConnection(row('Before'));
      testMemorySecrets.resetCounts();
      // Writes of the update: password 1 (applied), connection string 2.
      final error = StateError('connection string refused');
      testMemorySecrets.failOnCall(SecretsOp.write, 2, error);

      await expectLater(
        LocalDb.instance.updateConnection(ConnectionRow(
          id: id,
          type: 'postgresql',
          name: 'After',
          host: 'other-host',
          port: 5433,
          username: 'root',
          password: 'new-password',
          connectionString: 'postgres://root@other-host/db',
          createdAt: '2026-01-01T00:00:00Z',
        )),
        throwsA(same(error)),
      );

      final loaded = (await LocalDb.instance.getConnections(
        hydrateSecrets: true,
      ))
          .singleWhere((c) => c.id == id);
      expect(loaded.name, 'Before');
      expect(loaded.host, 'localhost');
      expect(loaded.password, 'db-password');
      expect(loaded.connectionString, 'postgres://admin@localhost/db');
    });
  });

  test(
      'updateConnection: when the restore is refused as well the first error '
      'is reported and the failed restore is logged (#1778)', () async {
    final id = await LocalDb.instance.addConnection(row('Before'));
    testMemorySecrets.resetCounts();
    final error = StateError('connection string refused');
    testMemorySecrets.failOnCall(SecretsOp.write, 2, error);
    // The restore writes the old password first (call 3).
    testMemorySecrets.failOnCall(
        SecretsOp.write, 3, StateError('keyring went away'));
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);

    await expectLater(
      LocalDb.instance.updateConnection(ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'After',
        host: 'other-host',
        port: 5433,
        username: 'root',
        password: 'new-password',
        connectionString: 'postgres://root@other-host/db',
        createdAt: '2026-01-01T00:00:00Z',
      )),
      throwsA(same(error)),
    );

    expect(
      printed.where((l) => l.contains('restore of connection $id')),
      isNotEmpty,
    );
    expect(printed.join('\n'), contains('keyring went away'));
    expect((await rowsNamed('Before')), hasLength(1));
  });

  group('a read that fails', () {
    test(
        'a refusal on the second key is "could not read", not "no password", '
        'and a retry reads both', () async {
      final id = await LocalDb.instance.addConnection(row('Read me'));
      testMemorySecrets.resetCounts();
      final cause = Exception('keyring is locked');
      testMemorySecrets.failOnCall(SecretsOp.read, 2, cause);

      await expectLater(
        ConnectionSecretsStore.readForConnection(id),
        throwsA(isA<SecretsStoreUnavailableException>()
            .having((e) => e.cause, 'cause', same(cause))),
      );
      expect(testMemorySecrets.readCalls, 2);

      final retry = await ConnectionSecretsStore.readForConnection(id);
      expect(retry.password, 'db-password');
      expect(retry.connectionString, 'postgres://admin@localhost/db');
    });

    test(
        'the list still loads while the keyring is down, rows without their '
        'password, and has them once it answers', () async {
      final id = await LocalDb.instance.addConnection(row('Locked list'));
      testMemorySecrets.failAlways(SecretsOp.read, Exception('locked'));

      final during = (await LocalDb.instance.getConnections(
        hydrateSecrets: true,
      ))
          .singleWhere((c) => c.id == id);
      expect(during.name, 'Locked list');
      expect(during.password, isNull);

      testMemorySecrets.heal(SecretsOp.read);
      final after = (await LocalDb.instance.getConnections(
        hydrateSecrets: true,
      ))
          .singleWhere((c) => c.id == id);
      expect(after.password, 'db-password');
    });
  });

  group('a retry after a refusal', () {
    test('addConnection stores the connection once the keyring answers',
        () async {
      testMemorySecrets.failAlways(SecretsOp.write, StateError('locked'));
      await expectLater(
        LocalDb.instance.addConnection(row('Retry add')),
        throwsA(isA<StateError>()),
      );
      expect(await rowsNamed('Retry add'), isEmpty);

      testMemorySecrets.heal(SecretsOp.write);
      final id = await LocalDb.instance.addConnection(row('Retry add'));

      expect(await rowsNamed('Retry add'), hasLength(1));
      final secrets = await ConnectionSecretsStore.readForConnection(id);
      expect(secrets.password, 'db-password');
      expect(secrets.connectionString, 'postgres://admin@localhost/db');
    });

    test('updateConnection applies the edit once the keyring answers',
        () async {
      final id = await LocalDb.instance.addConnection(row('Retry edit'));
      final edited = ConnectionRow(
        id: id,
        type: 'postgresql',
        name: 'Retry edit',
        host: 'localhost',
        port: 5432,
        username: 'admin',
        password: 'changed-password',
        connectionString: 'postgres://admin@localhost/db',
        createdAt: '2026-01-01T00:00:00Z',
      );

      testMemorySecrets.failNextWrite = StateError('locked');
      await expectLater(
        LocalDb.instance.updateConnection(edited),
        throwsA(isA<StateError>()),
      );
      expect(
        (await ConnectionSecretsStore.readForConnection(id)).password,
        'db-password',
      );

      await LocalDb.instance.updateConnection(edited);
      expect(
        (await ConnectionSecretsStore.readForConnection(id)).password,
        'changed-password',
      );
    });
  });
}
