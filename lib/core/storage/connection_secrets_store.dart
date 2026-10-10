import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Backend for reading/writing per-connection secrets (password, connection string).
/// In unit/widget tests, set [ConnectionSecretsStore.backend] to a memory implementation.
abstract class SecretsStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> delete(String key);
}

class _FlutterSecureStorageBackend implements SecretsStorageBackend {
  /// Desktop targets use the default platform options from the plugin.
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The system secret store (Keychain / Credential Manager / libsecret) did not
/// answer: it is locked, has no running secret service, or failed.
///
/// Distinct from "there is no such secret", which reads as null: a password
/// that could not be read must not be taken for a connection without one
/// (#1303).
class SecretsStoreUnavailableException implements Exception {
  SecretsStoreUnavailableException(this.cause);

  /// What the platform store threw.
  final Object cause;

  static const String message =
      'Could not read the saved credentials from the system keyring '
      '(Keychain / Credential Manager / libsecret).';

  /// What to do about it, for single-line surfaces.
  static const String hint =
      'Unlock the keyring or start the secret service, then try again';

  @override
  String toString() => '$message $hint ($cause)';
}

/// Stores connection passwords and connection strings outside of the SQLite file
/// using the platform secure store (Keychain / Credential Manager / libsecret).
class ConnectionSecretsStore {
  ConnectionSecretsStore._();

  /// Production uses OS-backed storage; tests override [backend] (see `test/flutter_test_config.dart`).
  static SecretsStorageBackend backend = _FlutterSecureStorageBackend();

  /// Identifies the current profile's local database (installed / portable /
  /// migrated-legacy — see `AppDataRoot`), so that two independent profile
  /// databases never collide in the shared OS keyring even when they each
  /// mint the same connection id (every profile DB starts its own
  /// `connections` autoincrement sequence at 1). [LocalDb] sets this once,
  /// right after opening its database, before any secret is read or written.
  static String? profileId;

  static const _legacyKeyPrefix = 'querya.v1.conn';

  static String _requireProfileId() {
    final id = profileId;
    if (id == null) {
      throw StateError(
        'ConnectionSecretsStore.profileId is not set; open LocalDb before '
        'reading or writing connection secrets.',
      );
    }
    return id;
  }

  static String _passwordKey(int connectionId) =>
      'querya.v1.profile.${_requireProfileId()}.conn.$connectionId.password';
  static String _connectionStringKey(int connectionId) =>
      'querya.v1.profile.${_requireProfileId()}.conn.$connectionId.connection_string';
  static String _sshPasswordKey(int connectionId) =>
      'querya.v1.profile.${_requireProfileId()}.conn.$connectionId.ssh_password';
  static String _sshPrivateKeyKey(int connectionId) =>
      'querya.v1.profile.${_requireProfileId()}.conn.$connectionId.ssh_private_key';
  static String _sshPassphraseKey(int connectionId) =>
      'querya.v1.profile.${_requireProfileId()}.conn.$connectionId.ssh_passphrase';
  static String _sshJumpPasswordKey(int connectionId) =>
      'querya.v1.profile.${_requireProfileId()}.conn.$connectionId.ssh_jump_password';

  /// Pre-#986 unnamespaced key format, kept only for [adoptLegacyKeysForConnection].
  static String _legacyPasswordKey(int connectionId) =>
      '$_legacyKeyPrefix.$connectionId.password';
  static String _legacyConnectionStringKey(int connectionId) =>
      '$_legacyKeyPrefix.$connectionId.connection_string';

  static Future<void> writeForConnection(
    int connectionId, {
    String? password,
    String? connectionString,
    String? sshPassword,
    String? sshPrivateKey,
    String? sshPassphrase,
    String? jumpPassword,
  }) async {
    await backend.write(_passwordKey(connectionId), password);
    await backend.write(_connectionStringKey(connectionId), connectionString);
    if (sshPassword != null || sshPrivateKey != null || sshPassphrase != null || jumpPassword != null) {
      await writeSshSecretsForConnection(
        connectionId,
        password: sshPassword,
        privateKey: sshPrivateKey,
        passphrase: sshPassphrase,
        jumpPassword: jumpPassword,
      );
    }
  }

  static Future<void> writeSshSecretsForConnection(
    int connectionId, {
    String? password,
    String? privateKey,
    String? passphrase,
    String? jumpPassword,
  }) async {
    await backend.write(_sshPasswordKey(connectionId), password);
    await backend.write(_sshPrivateKeyKey(connectionId), privateKey);
    await backend.write(_sshPassphraseKey(connectionId), passphrase);
    await backend.write(_sshJumpPasswordKey(connectionId), jumpPassword);
  }

  static Future<({
    String? password,
    String? privateKey,
    String? passphrase,
    String? jumpPassword,
  })> readSshSecretsForConnection(int connectionId) async {
    final String passwordKey, privateKeyKey, passphraseKey, jumpKey;
    try {
      passwordKey = _sshPasswordKey(connectionId);
      privateKeyKey = _sshPrivateKeyKey(connectionId);
      passphraseKey = _sshPassphraseKey(connectionId);
      jumpKey = _sshJumpPasswordKey(connectionId);
    } on StateError {
      return (
        password: null,
        privateKey: null,
        passphrase: null,
        jumpPassword: null,
      );
    }
    try {
      return (
        password: await backend.read(passwordKey),
        privateKey: await backend.read(privateKeyKey),
        passphrase: await backend.read(passphraseKey),
        jumpPassword: await backend.read(jumpKey),
      );
    } catch (e) {
      throw SecretsStoreUnavailableException(e);
    }
  }

  static Future<({String? password, String? connectionString})>
      readForConnection(
    int connectionId,
  ) async {
    final String passwordKey, connectionStringKey;
    try {
      passwordKey = _passwordKey(connectionId);
      connectionStringKey = _connectionStringKey(connectionId);
    } on StateError {
      // No profile yet (nothing was ever stored): same as no secrets.
      return (password: null, connectionString: null);
    }
    String? password;
    String? connectionString;
    try {
      password = await backend.read(passwordKey);
      connectionString = await backend.read(connectionStringKey);
    } catch (e) {
      throw SecretsStoreUnavailableException(e);
    }
    // Fallback: If either secret wasn't found under the namespaced key,
    // lazily check the legacy unnamespaced key (#1008). This guards against
    // transient keyring failures during the one-time DB upgrade migration,
    // and writes through to adopt the legacy secret immediately.
    if (password == null || connectionString == null) {
      try {
        String? legacyPassword;
        String? legacyConnectionString;
        if (password == null) {
          legacyPassword =
              await backend.read(_legacyPasswordKey(connectionId));
        }
        if (connectionString == null) {
          legacyConnectionString =
              await backend.read(_legacyConnectionStringKey(connectionId));
        }
        if (legacyPassword != null || legacyConnectionString != null) {
          final effectivePassword = password ?? legacyPassword;
          final effectiveConnectionString =
              connectionString ?? legacyConnectionString;
          await writeForConnection(
            connectionId,
            password: effectivePassword,
            connectionString: effectiveConnectionString,
          );
          if (legacyPassword != null) {
            try {
              await backend.delete(_legacyPasswordKey(connectionId));
            } catch (_) {}
          }
          if (legacyConnectionString != null) {
            try {
              await backend.delete(_legacyConnectionStringKey(connectionId));
            } catch (_) {}
          }
          password = effectivePassword;
          connectionString = effectiveConnectionString;
        }
      } catch (_) {
        // Best-effort lazy adoption; return whatever was already read.
      }
    }
    return (password: password, connectionString: connectionString);
  }

  static Future<void> deleteForConnection(int connectionId) async {
    await backend.delete(_passwordKey(connectionId));
    await backend.delete(_connectionStringKey(connectionId));
    await backend.delete(_sshPasswordKey(connectionId));
    await backend.delete(_sshPrivateKeyKey(connectionId));
    await backend.delete(_sshPassphraseKey(connectionId));
    await backend.delete(_sshJumpPasswordKey(connectionId));
    try {
      await backend.delete(_legacyPasswordKey(connectionId));
      await backend.delete(_legacyConnectionStringKey(connectionId));
    } catch (_) {}
  }

  /// One-time migration (issue #986): before keyring keys were namespaced by
  /// profile, every profile database shared the same `querya.v1.conn.<id>.*`
  /// keys, so two profiles with a connection of the same id could overwrite
  /// or delete each other's secret. Called by [LocalDb] for every existing
  /// connection when a database upgrades to schema version 9; adopts this
  /// profile's own legacy entry (if any) under the namespaced key, then
  /// removes the legacy entry so a *different* profile no longer sees it as
  /// "still shared". A no-op when no legacy entry exists for [connectionId].
  static Future<void> adoptLegacyKeysForConnection(int connectionId) async {
    String? legacyPassword;
    String? legacyConnectionString;
    try {
      legacyPassword = await backend.read(_legacyPasswordKey(connectionId));
      legacyConnectionString =
          await backend.read(_legacyConnectionStringKey(connectionId));
    } catch (_) {
      return;
    }
    if (legacyPassword == null && legacyConnectionString == null) return;
    try {
      await writeForConnection(
        connectionId,
        password: legacyPassword,
        connectionString: legacyConnectionString,
      );
    } catch (_) {
      return;
    }
    try {
      await backend.delete(_legacyPasswordKey(connectionId));
      await backend.delete(_legacyConnectionStringKey(connectionId));
    } catch (_) {
      // Best-effort cleanup; a leftover legacy key is harmless (it belongs to
      // whichever profile adopts it first) but should not fail the upgrade.
    }
  }
}
