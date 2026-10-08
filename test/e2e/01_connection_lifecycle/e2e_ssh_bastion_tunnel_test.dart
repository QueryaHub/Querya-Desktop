import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../support/fake_ssh.dart';
import '../helpers/e2e_app_harness.dart';

const _sshPassword = 'Bastion-Pw-7c1e';

/// A saved connection reaches its database through a bastion: configuration is
/// persisted without secrets, then the tunnel is opened from what was stored.
void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_ssh_');
  late FakeSshServer server;
  late SshTunnelManager manager;

  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  setUp(() {
    server = FakeSshServer(password: _sshPassword);
    manager = SshTunnelManager.forTesting(
      connector: server.connect,
      clientBuilder: server.build,
    );
  });
  tearDown(() => manager.closeAll());

  SshTunnelConfig config({String? fingerprint}) => SshTunnelConfig(
        enabled: true,
        host: 'bastion.example',
        port: 22,
        username: 'deploy',
        knownHostFingerprint: fingerprint,
        keepAliveIntervalSeconds: 0,
      );

  Future<ConnectionRow> save({String? fingerprint}) async {
    final base = ConnectionRow(
      type: 'postgresql',
      name: 'Behind bastion',
      host: 'db.internal',
      port: 5432,
      createdAt: DateTime.utc(2026).toIso8601String(),
      sshSecrets: SshTunnelSecrets(password: _sshPassword),
    ).withSshTunnelConfig(config(fingerprint: fingerprint));
    final id = await LocalDb.instance.addConnection(base);
    final stored = (await LocalDb.instance.getConnectionById(id))!;
    return stored;
  }

  test('configuration is stored without SSH secrets', () async {
    final row = await save();

    // Config round-trips from the non-secret driver options.
    final cfg = row.sshTunnelConfig!;
    expect(cfg.enabled, isTrue);
    expect(cfg.host, 'bastion.example');
    expect(cfg.username, 'deploy');
    expect(row.driverOptions, isNot(contains(_sshPassword)));

    // The password lives in the secure store only.
    final secrets =
        await ConnectionSecretsStore.readSshSecretsForConnection(row.id!);
    expect(secrets.password, _sshPassword);

    await LocalDb.instance.close();
    final files = app.dataDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('.db'));
    for (final f in files) {
      expect(String.fromCharCodes(f.readAsBytesSync()),
          isNot(contains(_sshPassword)),
          reason: f.path);
    }
  });

  test('the stored connection opens a loopback tunnel to the database',
      () async {
    final row = await save();
    final secrets = await ConnectionSecretsStore.readSshSecretsForConnection(
        row.id!);
    final tunnelSecrets = SshTunnelSecrets(password: secrets.password);

    final handle = await manager.openTunnel(
      config: row.sshTunnelConfig!,
      secrets: tunnelSecrets,
      remoteHost: row.host!,
      remotePort: row.port!,
    );

    expect(handle.localHost, '127.0.0.1');
    expect(handle.localPort, greaterThan(0));
    expect(tunnelSecrets.isEmpty, isTrue,
        reason: 'credentials are scrubbed after the handshake');

    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, handle.localPort);
    final reply = socket.cast<List<int>>().transform(utf8.decoder).first;
    socket.write('select 1');
    await socket.flush();
    expect(await reply.timeout(const Duration(seconds: 5)), 'SELECT 1');
    socket.destroy();
    expect(server.clients.single.forwards.single,
        (host: 'db.internal', port: 5432));

    await handle.release();
    expect(manager.activeSessionCount, 0);
  });

  test('Test SSH Connection reports success with the server fingerprint',
      () async {
    final row = await save();
    final r = await manager.testSshConnection(
      config: row.sshTunnelConfig!,
      secrets: SshTunnelSecrets(password: _sshPassword),
      testRemoteHost: row.host,
      testRemotePort: row.port,
    );
    expect(r.ok, isTrue);
    expect(r.serverFingerprint,
        SshTunnelManager.formatFingerprint(server.hostKey));
  });

  test('a wrong password and a changed host key are both refused', () async {
    final row = await save();

    final bad = await manager.testSshConnection(
      config: row.sshTunnelConfig!,
      secrets: SshTunnelSecrets(password: 'nope'),
    );
    expect(bad.ok, isFalse);

    final pinned = config(
        fingerprint:
            SshTunnelManager.formatFingerprint(server.hostKey));
    server.hostKey = server.hostKey..[0] = 99; // key changed after pinning
    await expectLater(
      manager.openTunnel(
        config: pinned,
        secrets: SshTunnelSecrets(password: _sshPassword),
        remoteHost: 'db.internal',
        remotePort: 5432,
      ),
      throwsA(isA<SshHostKeyMismatchException>()),
    );
    expect(manager.activeSessionCount, 0);
  });

  test('a passphrase-protected key is stored in the secure store and opens '
      'the tunnel', () async {
    const passphrase = 'Key-Passphrase-3d8f';
    final keyDir = await Directory.systemTemp.createTemp('e2e_ssh_key_');
    addTearDown(() => keyDir.deleteSync(recursive: true));
    final keyPath = p.join(keyDir.path, 'id_ed25519');
    try {
      final r = await Process.run('ssh-keygen',
          ['-q', '-t', 'ed25519', '-N', passphrase, '-f', keyPath]);
      if (r.exitCode != 0) {
        markTestSkipped('ssh-keygen failed');
        return;
      }
    } on ProcessException {
      markTestSkipped('ssh-keygen is not available');
      return;
    }
    final pem = File(keyPath).readAsStringSync();

    final cfg = config().copyWith(authType: SshAuthType.privateKey);
    final id = await LocalDb.instance.addConnection(ConnectionRow(
      type: 'postgresql',
      name: 'Key bastion',
      host: 'db.internal',
      port: 5432,
      createdAt: DateTime.utc(2026).toIso8601String(),
      sshSecrets: SshTunnelSecrets(privateKey: pem, passphrase: passphrase),
    ).withSshTunnelConfig(cfg));
    final row = (await LocalDb.instance.getConnectionById(id))!;

    expect(row.sshTunnelConfig!.authType, SshAuthType.privateKey);
    expect(row.driverOptions, isNot(contains(passphrase)));
    expect(row.driverOptions, isNot(contains('PRIVATE KEY')));

    final stored =
        await ConnectionSecretsStore.readSshSecretsForConnection(id);
    expect(stored.passphrase, passphrase);
    expect(stored.privateKey, pem);

    final secrets = SshTunnelSecrets(
        privateKey: stored.privateKey, passphrase: stored.passphrase);
    final handle = await manager.openTunnel(
      config: row.sshTunnelConfig!,
      secrets: secrets,
      remoteHost: row.host!,
      remotePort: row.port!,
    );
    expect(handle.localPort, greaterThan(0));
    expect(server.clients.last.passwordRequested, isFalse,
        reason: 'key auth must not fall back to a password');
    expect(secrets.isEmpty, isTrue);
    await handle.release();
  });
}
