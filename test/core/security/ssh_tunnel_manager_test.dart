import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/app/app_shutdown.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';

import '../../support/fake_ssh.dart';

SshTunnelConfig _config({
  SshAuthType authType = SshAuthType.password,
  String? fingerprint,
  String? privateKeyPath,
  String? jumpHost,
  String? jumpUsername,
  int keepAlive = 0,
}) =>
    SshTunnelConfig(
      enabled: true,
      host: 'bastion.example',
      port: 2222,
      username: 'deploy',
      authType: authType,
      knownHostFingerprint: fingerprint,
      privateKeyPath: privateKeyPath,
      jumpHost: jumpHost,
      jumpUsername: jumpUsername,
      keepAliveIntervalSeconds: keepAlive,
    );

Future<Socket> _dial(int port) =>
    Socket.connect(InternetAddress.loopbackIPv4, port);

Future<bool> _accepts(int port) async {
  try {
    final s = await _dial(port);
    s.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

void main() {
  late FakeSshServer server;
  late SshTunnelManager manager;
  late SshTunnelManager originalInstance;

  setUp(() {
    server = FakeSshServer();
    manager = SshTunnelManager.forTesting(
      connector: server.connect,
      clientBuilder: server.build,
    );
    originalInstance = SshTunnelManager.instance;
  });

  tearDown(() async {
    SshTunnelManager.instance = originalInstance;
    await manager.closeAll();
  });

  Future<SshTunnelHandle> open({
    SshTunnelConfig? config,
    SshTunnelSecrets? secrets,
    String remoteHost = 'db.internal',
    int remotePort = 5432,
  }) =>
      manager.openTunnel(
        config: config ?? _config(),
        secrets: secrets ?? SshTunnelSecrets(password: 'secret'),
        remoteHost: remoteHost,
        remotePort: remotePort,
      );

  group('loopback binding and ports', () {
    test('the tunnel is reported and reachable on 127.0.0.1', () async {
      final handle = await open();

      expect(handle.localHost, '127.0.0.1');
      expect(handle.remoteHost, 'db.internal');
      expect(handle.remotePort, 5432);
      expect(await _accepts(handle.localPort), isTrue);
    });

    test('the listener is not reachable through other local interfaces',
        () async {
      final handle = await open();
      final external = <InternetAddress>[];
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        external.addAll(iface.addresses.where((a) => !a.isLoopback));
      }
      if (external.isEmpty) {
        markTestSkipped('no non-loopback IPv4 interface on this machine');
        return;
      }

      for (final address in external) {
        await expectLater(
          Socket.connect(address, handle.localPort,
              timeout: const Duration(seconds: 2)),
          throwsA(isA<SocketException>()),
          reason: 'must not listen on ${address.address}',
        );
      }
    });

    test('each tunnel gets its own free ephemeral port', () async {
      final a = await open(remotePort: 5432);
      final b = await open(remotePort: 3306);
      final c = await open(remotePort: 6379);

      final ports = {a.localPort, b.localPort, c.localPort};
      expect(ports, hasLength(3));
      for (final port in ports) {
        expect(port, greaterThanOrEqualTo(1024));
      }
    });

    test('bytes written to the local port reach the remote target and back',
        () async {
      final handle = await open(remoteHost: 'db.internal', remotePort: 5432);

      final socket = await _dial(handle.localPort);
      final reply = socket.cast<List<int>>().transform(utf8.decoder).first;
      socket.write('select 1');
      await socket.flush();

      expect(await reply.timeout(const Duration(seconds: 5)), 'SELECT 1');
      socket.destroy();

      final client = server.clients.single;
      expect(client.forwards.single, (host: 'db.internal', port: 5432));
      expect(client.received.map(utf8.decode), ['select 1']);
    });
  });

  group('authentication', () {
    test('a password is supplied to the bastion', () async {
      await open(secrets: SshTunnelSecrets(password: 'secret'));

      final client = server.clients.single;
      expect(client.username, 'deploy');
      expect(client.suppliedPassword, 'secret');
      expect(server.connects.single, (host: 'bastion.example', port: 2222));
    });

    test('a wrong password fails with SshAuthenticationException', () async {
      await expectLater(
        open(secrets: SshTunnelSecrets(password: 'nope')),
        throwsA(
          isA<SshAuthenticationException>().having(
            (e) => e.message,
            'message',
            contains('deploy@bastion.example'),
          ),
        ),
      );

      expect(manager.activeSessionCount, 0);
      expect(server.clients.single.isClosed, isTrue);
    });

    test('an unreachable bastion is a connection failure naming the host',
        () async {
      server.failConnect = true;

      await expectLater(
        open(),
        throwsA(isA<SshConnectionException>().having(
          (e) => e.message,
          'message',
          allOf(contains('bastion.example:2222'), contains('failed')),
        )),
      );
      expect(manager.activeSessionCount, 0);
    });

    test('a reset during the handshake is not reported as a wrong password',
        () async {
      server.failHandshake = const SocketException('Connection reset by peer');

      await expectLater(
        open(),
        throwsA(isA<SshConnectionException>().having(
          (e) => e.message,
          'message',
          allOf(contains('bastion.example:2222'), contains('reset by peer')),
        )),
      );
    });

    test('a rejected jump host login names the jump host and user', () async {
      server.userPasswords['jumper'] = 'right';

      await expectLater(
        open(
          config: _config(jumpHost: 'jump.example', jumpUsername: 'jumper'),
          secrets: SshTunnelSecrets(password: 'secret', jumpPassword: 'wrong'),
        ),
        throwsA(isA<SshAuthenticationException>().having(
          (e) => e.message,
          'message',
          allOf(contains('jumper@jump.example')),
        )),
      );
      expect(manager.activeSessionCount, 0);
    });

    test('a jump host is dialed first and the bastion is reached through it',
        () async {
      server.userPasswords['jumper'] = 'jump-secret';

      await open(
        config: _config(jumpHost: 'jump.example', jumpUsername: 'jumper'),
        secrets: SshTunnelSecrets(
          password: 'secret',
          jumpPassword: 'jump-secret',
        ),
      );

      expect(server.connects.single, (host: 'jump.example', port: 22));
      expect(server.clients, hasLength(2));
      final jump = server.clients[0];
      final bastion = server.clients[1];
      expect(jump.username, 'jumper');
      expect(jump.suppliedPassword, 'jump-secret');
      expect(jump.forwards.single, (host: 'bastion.example', port: 2222));
      expect(bastion.username, 'deploy');
      expect(bastion.suppliedPassword, 'secret');
    });

    test('the jump host falls back to the main password', () async {
      await open(
        config: _config(jumpHost: 'jump.example'),
        secrets: SshTunnelSecrets(password: 'secret'),
      );

      expect(server.clients[0].username, 'deploy');
      expect(server.clients[0].suppliedPassword, 'secret');
    });
  });

  group('private keys', () {
    late Directory keyDir;
    String? ed25519;
    String? ed25519Encrypted;
    String? rsa;
    String? rsaEncrypted;
    const passphrase = 'correct horse';

    Future<String?> generate(
      String name,
      List<String> typeArgs, {
      String pass = '',
    }) async {
      final path = p.join(keyDir.path, name);
      final r = await Process.run(
        'ssh-keygen',
        ['-q', ...typeArgs, '-N', pass, '-C', name, '-f', path],
      );
      return r.exitCode == 0 ? path : null;
    }

    setUpAll(() async {
      keyDir = await Directory.systemTemp.createTemp('ssh_tunnel_keys_');
      try {
        ed25519 = await generate('ed25519', ['-t', 'ed25519']);
        ed25519Encrypted = await generate(
          'ed25519_enc',
          ['-t', 'ed25519'],
          pass: passphrase,
        );
        rsa = await generate('rsa', ['-t', 'rsa', '-b', '2048', '-m', 'PEM']);
        rsaEncrypted = await generate(
          'rsa_enc',
          ['-t', 'rsa', '-b', '2048', '-m', 'PEM'],
          pass: passphrase,
        );
      } on ProcessException {
        // ssh-keygen is not installed: the key tests below skip themselves.
      }
    });

    tearDownAll(() => keyDir.deleteSync(recursive: true));

    bool keysAvailable() {
      if (ed25519 == null) {
        markTestSkipped('ssh-keygen is not available');
        return false;
      }
      return true;
    }

    test('an unencrypted Ed25519 key authenticates', () async {
      if (!keysAvailable()) return;
      await open(
        config: _config(authType: SshAuthType.privateKey),
        secrets: SshTunnelSecrets(privateKey: File(ed25519!).readAsStringSync()),
      );

      expect(server.clients.single.identities, hasLength(1));
      expect(server.clients.single.passwordRequested, isFalse);
    });

    test('an unencrypted RSA key authenticates', () async {
      if (!keysAvailable()) return;
      await open(
        config: _config(authType: SshAuthType.privateKey),
        secrets: SshTunnelSecrets(privateKey: File(rsa!).readAsStringSync()),
      );

      expect(server.clients.single.identities, hasLength(1));
    });

    test('keys protected by a passphrase authenticate', () async {
      if (!keysAvailable()) return;
      final keys = [ed25519Encrypted!, rsaEncrypted!];
      for (var i = 0; i < keys.length; i++) {
        final handle = await open(
          config: _config(authType: SshAuthType.privateKey),
          secrets: SshTunnelSecrets(
            privateKey: File(keys[i]).readAsStringSync(),
            passphrase: passphrase,
          ),
          // A distinct target per key so each one gets its own session.
          remotePort: 7000 + i,
        );
        expect(handle.localPort, greaterThan(0), reason: keys[i]);
      }
      expect(server.clients, hasLength(2));
      expect(server.clients.every((c) => c.identities!.length == 1), isTrue);
    });

    test('a wrong passphrase is reported as a key parse failure', () async {
      if (!keysAvailable()) return;
      await expectLater(
        open(
          config: _config(authType: SshAuthType.privateKey),
          secrets: SshTunnelSecrets(
            privateKey: File(ed25519Encrypted!).readAsStringSync(),
            passphrase: 'wrong',
          ),
        ),
        throwsA(
          isA<SshAuthenticationException>().having(
            (e) => e.message,
            'message',
            startsWith('Failed to parse private key'),
          ),
        ),
      );
      expect(manager.activeSessionCount, 0);
    });

    test('garbage instead of a key is rejected', () async {
      await expectLater(
        open(
          config: _config(authType: SshAuthType.privateKey),
          secrets: SshTunnelSecrets(privateKey: 'not a key'),
        ),
        throwsA(isA<SshAuthenticationException>()),
      );
    });

    test('the key is read from privateKeyPath when no key content is stored',
        () async {
      if (!keysAvailable()) return;
      await open(
        config: _config(
          authType: SshAuthType.privateKey,
          privateKeyPath: ed25519,
        ),
        secrets: SshTunnelSecrets(),
      );

      expect(server.clients.single.identities, hasLength(1));
    });

    test('the server can reject the key', () async {
      if (!keysAvailable()) return;
      server.acceptPublicKeys = false;

      await expectLater(
        open(
          config: _config(authType: SshAuthType.privateKey),
          secrets:
              SshTunnelSecrets(privateKey: File(ed25519!).readAsStringSync()),
        ),
        throwsA(isA<SshAuthenticationException>()),
      );
    });
  });

  group('in-memory secret scrubbing', () {
    test('credentials are cleared once the handshake succeeds', () async {
      final secrets = SshTunnelSecrets(
        password: 'secret',
        privateKey: 'unused',
        passphrase: 'unused',
        jumpPassword: 'unused',
      );

      await open(secrets: secrets);

      expect(secrets.isEmpty, isTrue);
      expect(secrets.password, isNull);
      expect(secrets.privateKey, isNull);
      expect(secrets.passphrase, isNull);
      expect(secrets.jumpPassword, isNull);
    });

    test('credentials handed to a reused tunnel are cleared too', () async {
      await open();
      final second = SshTunnelSecrets(password: 'secret');

      await open(secrets: second);

      expect(server.clients, hasLength(1));
      expect(second.isEmpty, isTrue);
    });
  });

  group('host key verification', () {
    final hostKey = [9, 8, 7, 6, 5];
    final hexFingerprint = sha256.convert(hostKey).toString();

    test('formatFingerprint is the SHA-256 hex digest', () {
      expect(
        SshTunnelManager.formatFingerprint(Uint8List.fromList(hostKey)),
        hexFingerprint,
      );
    });

    test('a matching pinned fingerprint is accepted', () async {
      server.hostKey = Uint8List.fromList(hostKey);

      await open(config: _config(fingerprint: hexFingerprint));

      expect(manager.activeSessionCount, 1);
    });

    test('colon-separated, upper-case fingerprints still match', () async {
      server.hostKey = Uint8List.fromList(hostKey);
      final pairs = [
        for (var i = 0; i < hexFingerprint.length; i += 2)
          hexFingerprint.substring(i, i + 2).toUpperCase(),
      ];

      await open(config: _config(fingerprint: pairs.join(':')));

      expect(manager.activeSessionCount, 1);
    });

    test('a changed host key is blocked as a possible man-in-the-middle',
        () async {
      server.hostKey = Uint8List.fromList(hostKey);

      await expectLater(
        open(config: _config(fingerprint: 'aa' * 32)),
        throwsA(
          isA<SshHostKeyMismatchException>().having(
            (e) => e.message,
            'message',
            allOf(contains('bastion.example'), contains(hexFingerprint)),
          ),
        ),
      );

      expect(manager.activeSessionCount, 0);
      expect(server.clients.single.isClosed, isTrue);
      expect(server.clients.single.passwordRequested, isFalse,
          reason: 'the password must not be sent to an unverified host');
    });

    test('a mismatch also closes the jump host connection', () async {
      server.hostKey = Uint8List.fromList(hostKey);

      await expectLater(
        open(config: _config(fingerprint: 'aa' * 32, jumpHost: 'jump.example')),
        throwsA(isA<SshHostKeyMismatchException>()),
      );

      expect(server.clients, hasLength(2));
      expect(server.clients.every((c) => c.isClosed), isTrue);
    });

    test('without a pinned fingerprint the first key is trusted', () async {
      await open(config: _config());

      expect(manager.activeSessionCount, 1);
    });
  });

  group('testSshConnection', () {
    test('a disabled tunnel is trivially ok', () async {
      final r = await manager.testSshConnection(
        config: const SshTunnelConfig(),
        secrets: SshTunnelSecrets(),
      );

      expect(r.ok, isTrue);
      expect(server.connects, isEmpty);
    });

    test('empty host and username are reported', () async {
      final noHost = await manager.testSshConnection(
        config: const SshTunnelConfig(enabled: true, username: 'u'),
        secrets: SshTunnelSecrets(),
      );
      final noUser = await manager.testSshConnection(
        config: const SshTunnelConfig(enabled: true, host: 'h'),
        secrets: SshTunnelSecrets(),
      );

      expect(noHost.ok, isFalse);
      expect(noHost.error, contains('host'));
      expect(noUser.ok, isFalse);
      expect(noUser.error, contains('username'));
    });

    test('success returns the server fingerprint and closes the client',
        () async {
      server.hostKey = Uint8List.fromList([1, 1, 2, 3]);

      final r = await manager.testSshConnection(
        config: _config(),
        secrets: SshTunnelSecrets(password: 'secret'),
        testRemoteHost: 'db.internal',
        testRemotePort: 5432,
      );

      expect(r.ok, isTrue);
      expect(
        r.serverFingerprint,
        SshTunnelManager.formatFingerprint(server.hostKey),
      );
      expect(server.clients.single.forwards.single,
          (host: 'db.internal', port: 5432));
      expect(server.clients.single.isClosed, isTrue);
      expect(manager.activeSessionCount, 0, reason: 'a test opens no tunnel');
    });

    test('bad credentials are reported without throwing', () async {
      final r = await manager.testSshConnection(
        config: _config(),
        secrets: SshTunnelSecrets(password: 'wrong'),
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('SSH Connection failed'));
      expect(server.clients.single.isClosed, isTrue);
    });
  });

  group('lifecycle', () {
    test('the same target shares one session and is ref-counted', () async {
      final a = await open();
      final b = await open(secrets: SshTunnelSecrets(password: 'secret'));

      expect(b.localPort, a.localPort);
      expect(manager.activeSessionCount, 1);
      expect(server.clients, hasLength(1));
      expect(server.connects, hasLength(1));

      await a.release();
      expect(manager.activeSessionCount, 1);
      expect(await _accepts(b.localPort), isTrue,
          reason: 'one holder is left');

      await b.release();
      expect(manager.activeSessionCount, 0);
      expect(await _accepts(b.localPort), isFalse);
      expect(server.clients.single.isClosed, isTrue);
    });

    test('releasing the same handle twice drops only one reference', () async {
      final a = await open();
      final b = await open();

      await a.release();
      await a.release();

      expect(manager.activeSessionCount, 1);
      expect(await _accepts(b.localPort), isTrue);
    });

    test('different targets get separate sessions', () async {
      final db = await open(remotePort: 5432);
      final cache = await open(remotePort: 6379);

      expect(manager.activeSessionCount, 2);
      expect(server.clients, hasLength(2));

      await db.release();
      expect(await _accepts(db.localPort), isFalse);
      expect(await _accepts(cache.localPort), isTrue);
    });

    test('a dropped SSH connection is replaced, not reused', () async {
      final first = await open();
      unawaited(server.clients.single.close());

      final second = await open();

      expect(server.clients, hasLength(2));
      expect(second.localPort, isNot(first.localPort));
      expect(manager.activeSessionCount, 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await _accepts(first.localPort), isFalse,
          reason: 'the stale listener must be closed');
      expect(await _accepts(second.localPort), isTrue);
    });

    test('a handle from a replaced session cannot release its successor',
        () async {
      final stale = await open();
      unawaited(server.clients.single.close());
      final fresh = await open();

      await stale.release();

      expect(manager.activeSessionCount, 1);
      expect(await _accepts(fresh.localPort), isTrue);
    });

    test('closeAll tears down every tunnel', () async {
      final a = await open(remotePort: 1111);
      final b = await open(remotePort: 2222);

      await manager.closeAll();

      expect(manager.activeSessionCount, 0);
      expect(await _accepts(a.localPort), isFalse);
      expect(await _accepts(b.localPort), isFalse);
      expect(server.clients.every((c) => c.isClosed), isTrue);
    });

    test('releasing a handle after closeAll is harmless', () async {
      final a = await open();
      await manager.closeAll();

      await a.release();

      expect(manager.activeSessionCount, 0);
    });

    test('app shutdown closes tunnels that are still open', () async {
      SshTunnelManager.instance = manager;
      final handle = await open();

      await disconnectAllExternalServices();

      expect(manager.activeSessionCount, 0);
      expect(await _accepts(handle.localPort), isFalse);
    });
  });

  group('keep-alive', () {
    test('pings the server periodically and stops when the tunnel closes',
        () async {
      final handle = await open(config: _config(keepAlive: 1));
      final client = server.clients.single;

      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(client.pingCount, greaterThanOrEqualTo(2));

      await handle.release();
      final afterClose = client.pingCount;
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(client.pingCount, afterClose);
    });

    test('a zero interval disables pings', () async {
      await open(config: _config(keepAlive: 0));

      await Future<void>.delayed(const Duration(milliseconds: 1300));

      expect(server.clients.single.pingCount, 0);
    });
  });
}
