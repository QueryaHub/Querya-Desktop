import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';

import '../../support/fake_ssh.dart';

/// #1313: forceClose / disconnect during connect().
void main() {
  late FakeSshServer server;
  late SshTunnelManager manager;
  late SshTunnelManager original;

  setUp(() {
    server = FakeSshServer();
    manager = SshTunnelManager.forTesting(
      connector: server.connect,
      clientBuilder: server.build,
    );
    original = SshTunnelManager.instance;
    SshTunnelManager.instance = manager;
  });

  tearDown(() async {
    SshTunnelManager.instance = original;
    await manager.closeAll();
  });

  MysqlConnection tunnelled() => MysqlConnection(
        id: 0,
        name: 'm',
        host: 'db.internal',
        port: 3306,
        sshConfig: const SshTunnelConfig(
          enabled: true,
          host: 'bastion.example',
          port: 22,
          username: 'deploy',
        ),
        sshSecrets: SshTunnelSecrets(password: 'secret'),
      );

  for (final closer in <(String, Future<void> Function(MysqlConnection))>[
    ('forceClose', (c) => c.forceClose()),
    ('disconnect', (c) => c.disconnect()),
  ]) {
    test('${closer.$1} while the tunnel is being opened ends the attempt '
        'and releases the tunnel', () async {
      server.connectDelay = const Duration(milliseconds: 300);
      final c = tunnelled();
      final started = DateTime.now();

      final attempt = c.connect(connectTimeoutMs: 6000);
      final outcome = expectLater(attempt, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await closer.$2(c);
      await outcome;

      // It stopped when the tunnel came up, not after the 6 s handshake wait.
      expect(DateTime.now().difference(started).inSeconds, lessThan(3));
      expect(c.isConnected, isFalse);
      expect(manager.activeSessionCount, 0,
          reason: 'the tunnel this attempt opened was released');
    });
  }

  test('a connect after a forceClose starts a new attempt', () async {
    server.connectDelay = const Duration(milliseconds: 200);
    final c = tunnelled();

    final first = c.connect(connectTimeoutMs: 400);
    final firstOutcome = expectLater(first, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.forceClose();

    // Not the failing attempt that was overtaken.
    final second = c.connect(connectTimeoutMs: 400);
    expect(identical(first, second), isFalse);
    await firstOutcome;
    await second.then<void>((_) {}, onError: (_) {});
  });
}
