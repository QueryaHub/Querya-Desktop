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

  /// Pre-#986 unnamespaced key format, kept only for [adoptLegacyKeysForConnection].
  static String _legacyPasswordKey(int connectionId) =>
      '$_legacyKeyPrefix.$connectionId.password';
  static String _legacyConnectionStringKey(int connectionId) =>
      '$_legacyKeyPrefix.$connectionId.connection_string';

  static Future<void> writeForConnection(
    int connectionId, {
    String? password,
    String? connectionString,
  }) async {
    await backend.write(_passwordKey(connectionId), password);
    await backend.write(_connectionStringKey(connectionId), connectionString);
  }

  static Future<({String? password, String? connectionString})>
      readForConnection(
    int connectionId,
  ) async {
    try {
      var password = await backend.read(_passwordKey(connectionId));
      var connectionString =
          await backend.read(_connectionStringKey(connectionId));

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
    } catch (_) {
      return (password: null, connectionString: null);
    }
  }

  static Future<void> deleteForConnection(int connectionId) async {
    await backend.delete(_passwordKey(connectionId));
    await backend.delete(_connectionStringKey(connectionId));
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
