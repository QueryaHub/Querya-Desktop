import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/ssh_tunnel_host.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';

class _Host with SshTunnelHost {
  _Host(this.sshConfig);

  @override
  final SshTunnelConfig? sshConfig;
  @override
  final SshTunnelSecrets? sshSecrets = null;

  Future<SshTunnelHandle?> open() => openSshTunnel(id: 0, host: 'db', port: 5432);
  Future<void> release() => releaseSshTunnel();
}

void main() {
  test('no tunnel is opened without a config or when it is disabled', () async {
    expect(await _Host(null).open(), isNull);
    expect(await _Host(const SshTunnelConfig(enabled: false)).open(), isNull);
  });

  test('releasing with no tunnel open is harmless and leaves no handle', () async {
    final host = _Host(null);
    await host.release();
    expect(host.sshTunnelHandle, isNull);
  });
}
