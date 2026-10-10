import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Merges existing SSH secrets from secure store when edit form fields are left blank.
Future<SshTunnelSecrets> mergeSshSecretsForConnectionUpdate({
  required int connectionId,
  required SshTunnelSecrets editedSecrets,
}) async {
  final prev =
      await ConnectionSecretsStore.readSshSecretsForConnection(connectionId);
  return SshTunnelSecrets(
    password: (editedSecrets.password != null &&
            editedSecrets.password!.isNotEmpty)
        ? editedSecrets.password
        : prev.password,
    privateKey: (editedSecrets.privateKey != null &&
            editedSecrets.privateKey!.isNotEmpty)
        ? editedSecrets.privateKey
        : prev.privateKey,
    passphrase: (editedSecrets.passphrase != null &&
            editedSecrets.passphrase!.isNotEmpty)
        ? editedSecrets.passphrase
        : prev.passphrase,
    jumpPassword: (editedSecrets.jumpPassword != null &&
            editedSecrets.jumpPassword!.isNotEmpty)
        ? editedSecrets.jumpPassword
        : prev.jumpPassword,
  );
}

/// The secrets a *Test Connection* or *Test SSH connection* run uses (#1302).
///
/// An edit form never shows stored secrets, so a blank field means "the saved
/// one", exactly as in [mergeSecretsForConnectionUpdate]; testing with the
/// blank would fail with *Authentication failed* for a correct password. The
/// result is read-only for the caller: nothing is written, and the SSH secrets
/// are always a copy, because opening a tunnel clears what it is handed and
/// the form goes on using its own.
Future<
    ({
      String? password,
      String? connectionString,
      SshTunnelSecrets? sshSecrets,
    })> secretsForConnectionTest({
  required int? connectionId,
  required String? password,
  required String? connectionString,
  required SshTunnelSecrets? sshSecrets,
  bool useSavedPassword = true,
}) async {
  final id = connectionId;
  if (id == null || id <= 0) {
    return (
      password: password,
      connectionString: connectionString,
      sshSecrets: sshSecrets?.copy(),
    );
  }
  final prev = await ConnectionSecretsStore.readForConnection(id);
  // "Remove the saved password" is ticked: test without it (#1311).
  final effectivePassword = (password == null || password.isEmpty)
      ? (useSavedPassword ? prev.password : null)
      : password;
  var uri = connectionString;
  if (uri != null && uri.trim().isNotEmpty) {
    uri = injectUriPasswordIfMissing(uri, effectivePassword);
  }
  return (
    password: effectivePassword,
    connectionString: uri,
    sshSecrets: sshSecrets == null
        ? null
        : await mergeSshSecretsForConnectionUpdate(
            connectionId: id,
            editedSecrets: sshSecrets,
          ),
  );
}

/// Keeps previous secure-store secrets when edit form fields are left blank.
///
/// [ConnectionSecretsStore.writeForConnection] deletes empty values — callers
/// must merge before [LocalDb.updateConnection].
Future<ConnectionRow> mergeSecretsForConnectionUpdate(
  ConnectionRow edited,
) async {
  final id = edited.id;
  if (id == null) {
    throw ArgumentError('edited.id is required for secret merge');
  }
  final prev = await ConnectionSecretsStore.readForConnection(id);

  final passwordEmpty =
      edited.password == null || edited.password!.trim().isEmpty;
  // A blank field keeps the saved password, unless the user asked to remove
  // it (#1311). A password typed together with the request wins: it replaces.
  final String? password = edited.removeSavedPassword && passwordEmpty
      ? null
      : (passwordEmpty ? prev.password : edited.password);

  var connectionString = edited.connectionString;
  if (connectionString == null || connectionString.trim().isEmpty) {
    // Host-mode edit: do not resurrect a previous URI.
    connectionString = null;
  } else {
    connectionString = injectUriPasswordIfMissing(connectionString, password);
  }

  SshTunnelSecrets? sshSecrets = edited.sshSecrets;
  if (sshSecrets != null) {
    sshSecrets = await mergeSshSecretsForConnectionUpdate(
      connectionId: id,
      editedSecrets: sshSecrets,
    );
  }

  return edited.copyWith(
    password: password,
    connectionString: connectionString,
    sshSecrets: sshSecrets,
    clearPassword: password == null,
    clearConnectionString: connectionString == null,
  );
}

/// Strips userinfo password so edit forms never show stored secrets.
String? redactUriPassword(String? uri) {
  if (uri == null || uri.trim().isEmpty) return uri;
  final parsed = Uri.tryParse(uri.trim());
  if (parsed == null) return uri;
  final info = parsed.userInfo;
  if (info.isEmpty || !info.contains(':')) return uri;
  final user = info.split(':').first;
  return parsed.replace(userInfo: user).toString();
}

/// Puts [password] into URI userinfo when the URI has a user but no password.
@visibleForTesting
String injectUriPasswordIfMissing(String uri, String? password) {
  if (password == null || password.isEmpty) return uri;
  final parsed = Uri.tryParse(uri.trim());
  if (parsed == null) return uri;
  final info = parsed.userInfo;
  if (info.isEmpty) return uri;
  final parts = info.split(':');
  if (parts.length >= 2 && parts.sublist(1).join(':').isNotEmpty) {
    return uri;
  }
  final user = parts.first;
  // `Uri.replace` rejects a raw `@`, `/`, `#` and the like in the userinfo
  // (FormatException); the password goes in percent-encoded, as it is read.
  return parsed
      .replace(userInfo: '$user:${Uri.encodeComponent(password)}')
      .toString();
}
