import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

/// The SSH tunnel of a database connection: the same steps for every driver.
///
/// The class gives [sshConfig] and [sshSecrets]; the mixin holds the open
/// tunnel, opens it with the stored secrets when none were passed in, and
/// releases it.
mixin SshTunnelHost {
  SshTunnelConfig? get sshConfig;
  SshTunnelSecrets? get sshSecrets;

  SshTunnelHandle? _sshTunnelHandle;

  SshTunnelHandle? get sshTunnelHandle => _sshTunnelHandle;

  /// Opens the tunnel to [host]:[port] when the connection has one enabled,
  /// else null. The handle is not kept: pass it to [adoptSshTunnel] once the
  /// connect attempt is still the current one.
  @protected
  Future<SshTunnelHandle?> openSshTunnel({
    required int id,
    required String host,
    required int port,
  }) async {
    final config = sshConfig;
    if (config == null || !config.enabled) return null;
    var secrets = sshSecrets;
    if (secrets == null && id > 0) {
      final stored =
          await ConnectionSecretsStore.readSshSecretsForConnection(id);
      secrets = SshTunnelSecrets(
        password: stored.password,
        privateKey: stored.privateKey,
        passphrase: stored.passphrase,
        jumpPassword: stored.jumpPassword,
      );
    }
    return SshTunnelManager.instance.openTunnel(
      config: config,
      secrets: secrets ?? SshTunnelSecrets(),
      remoteHost: host,
      remotePort: port,
    );
  }

  @protected
  void adoptSshTunnel(SshTunnelHandle? handle) => _sshTunnelHandle = handle;

  /// Releases the open tunnel, if any. A failing release is logged under
  /// [logLabel] when given and ignored otherwise.
  @protected
  Future<void> releaseSshTunnel({String? logLabel}) async {
    final handle = _sshTunnelHandle;
    _sshTunnelHandle = null;
    try {
      await handle?.release();
    } catch (e) {
      if (logLabel != null) debugPrint('$logLabel: $e');
    }
  }

  /// Forgets [handle] when it is the one kept (a superseded connect attempt).
  @protected
  void forgetSshTunnel(SshTunnelHandle? handle) {
    if (identical(_sshTunnelHandle, handle)) _sshTunnelHandle = null;
  }
}
