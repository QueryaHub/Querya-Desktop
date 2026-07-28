import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

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
  final password = passwordEmpty ? prev.password : edited.password;

  var connectionString = edited.connectionString;
  if (connectionString == null || connectionString.trim().isEmpty) {
    // Host-mode edit: do not resurrect a previous URI.
    connectionString = null;
  } else {
    connectionString = injectUriPasswordIfMissing(connectionString, password);
  }

  return edited.copyWith(
    password: password,
    connectionString: connectionString,
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
  return parsed.replace(userInfo: '$user:$password').toString();
}
