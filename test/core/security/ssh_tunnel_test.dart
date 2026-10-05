import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

void main() {
  group('SshTunnelConfig', () {
    test('default configuration has enabled=false and port=22', () {
      const config = SshTunnelConfig();
      expect(config.enabled, isFalse);
      expect(config.port, equals(22));
      expect(config.authType, equals(SshAuthType.password));
      expect(config.keepAliveIntervalSeconds, equals(30));
    });

    test('serializes to and from Map correctly', () {
      const config = SshTunnelConfig(
        enabled: true,
        host: 'bastion.example.com',
        port: 2222,
        username: 'jumpuser',
        authType: SshAuthType.privateKey,
        privateKeyPath: '/home/user/.ssh/id_ed25519',
        knownHostFingerprint: 'SHA256:abc123xyz',
        keepAliveIntervalSeconds: 15,
        connectTimeoutSeconds: 10,
        jumpHost: 'proxy.internal',
        jumpPort: 22,
        jumpUsername: 'admin',
      );

      final map = config.toMap();
      final restored = SshTunnelConfig.fromMap(map);

      expect(restored, equals(config));
      expect(restored.enabled, isTrue);
      expect(restored.host, equals('bastion.example.com'));
      expect(restored.port, equals(2222));
      expect(restored.username, equals('jumpuser'));
      expect(restored.authType, equals(SshAuthType.privateKey));
      expect(restored.privateKeyPath, equals('/home/user/.ssh/id_ed25519'));
      expect(restored.knownHostFingerprint, equals('SHA256:abc123xyz'));
      expect(restored.keepAliveIntervalSeconds, equals(15));
      expect(restored.jumpHost, equals('proxy.internal'));
      expect(restored.jumpPort, equals(22));
      expect(restored.jumpUsername, equals('admin'));
    });

    test('JSON serialization round-trip', () {
      const config = SshTunnelConfig(
        enabled: true,
        host: 'ssh.server.net',
        port: 22,
        username: 'dev',
        authType: SshAuthType.sshAgent,
      );

      final json = config.toJson();
      final restored = SshTunnelConfig.fromJson(json);

      expect(restored, equals(config));
    });

    test('copyWith updates properties correctly', () {
      const config = SshTunnelConfig(host: 'old.host', port: 22);
      final updated = config.copyWith(host: 'new.host', port: 2222);

      expect(updated.host, equals('new.host'));
      expect(updated.port, equals(2222));
      expect(updated.enabled, isFalse);
    });
  });

  group('SshTunnelSecrets', () {
    test('reports empty / non-empty status accurately', () {
      final secrets = SshTunnelSecrets();
      expect(secrets.isEmpty, isTrue);
      expect(secrets.hasAny, isFalse);

      secrets.password = 'supersecret';
      expect(secrets.isEmpty, isFalse);
      expect(secrets.hasAny, isTrue);

      secrets.password = '';
      secrets.privateKey = '-----BEGIN OPENSSH PRIVATE KEY-----';
      expect(secrets.isEmpty, isFalse);
      expect(secrets.hasAny, isTrue);
    });

    test('zero() clears all in-memory buffers', () {
      final secrets = SshTunnelSecrets(
        password: 'pass',
        privateKey: 'key',
        passphrase: 'phrase',
        jumpPassword: 'jumppass',
      );

      expect(secrets.hasAny, isTrue);

      secrets.zero();

      expect(secrets.password, isNull);
      expect(secrets.privateKey, isNull);
      expect(secrets.passphrase, isNull);
      expect(secrets.jumpPassword, isNull);
      expect(secrets.isEmpty, isTrue);
    });
  });

  group('ConnectionRow SSH integration', () {
    test('encodes and decodes SshTunnelConfig in driverOptions', () {
      const row = ConnectionRow(
        type: 'postgresql',
        name: 'Remote PG via Bastion',
        createdAt: '2026-10-05T00:00:00Z',
      );

      expect(row.sshTunnelConfig, isNull);

      const ssh = SshTunnelConfig(
        enabled: true,
        host: 'bastion.company.org',
        port: 22,
        username: 'ops',
      );

      final updated = row.withSshTunnelConfig(ssh);
      expect(updated.sshTunnelConfig, equals(ssh));
      expect(updated.driverOptions, contains('"ssh_tunnel"'));

      // Disabling SSH tunnel removes the key from driverOptions
      final disabled = updated.withSshTunnelConfig(const SshTunnelConfig(enabled: false));
      expect(disabled.sshTunnelConfig, isNull);
      expect(disabled.driverOptions, isNot(contains('"ssh_tunnel"')));
    });

    test('withoutSecrets wipes transient sshSecrets', () {
      final secrets = SshTunnelSecrets(password: 'secret');
      final row = ConnectionRow(
        type: 'postgresql',
        name: 'Test',
        password: 'dbpass',
        createdAt: '2026-10-05T00:00:00Z',
        sshSecrets: secrets,
      );

      expect(row.hasSecrets, isTrue);
      expect(row.sshSecrets, isNotNull);

      final cleaned = row.withoutSecrets();
      expect(cleaned.password, isNull);
      expect(cleaned.sshSecrets, isNull);
      expect(cleaned.hasSecrets, isFalse);
    });

    test('toPersistenceMap never leaks password, connectionString, or sshSecrets', () {
      final secrets = SshTunnelSecrets(password: 'secret');
      final row = ConnectionRow(
        type: 'postgresql',
        name: 'Test',
        password: 'dbpass',
        connectionString: 'postgresql://user:pass@host/db',
        createdAt: '2026-10-05T00:00:00Z',
        sshSecrets: secrets,
      );

      final map = row.toPersistenceMap();
      expect(map['password'], isNull);
      expect(map['connection_string'], isNull);
      expect(map.containsKey('ssh_secrets'), isFalse);
      expect(map.containsKey('sshSecrets'), isFalse);
    });
  });
}
