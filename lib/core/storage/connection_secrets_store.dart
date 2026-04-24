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

  static const _keyPrefix = 'querya.v1.conn';

  static String _passwordKey(int connectionId) => '$_keyPrefix.$connectionId.password';
  static String _connectionStringKey(int connectionId) =>
      '$_keyPrefix.$connectionId.connection_string';

  static Future<void> writeForConnection(
    int connectionId, {
    String? password,
    String? connectionString,
  }) async {
    await backend.write(_passwordKey(connectionId), password);
    await backend.write(_connectionStringKey(connectionId), connectionString);
  }

  static Future<({String? password, String? connectionString})> readForConnection(
    int connectionId,
  ) async {
    final password = await backend.read(_passwordKey(connectionId));
    final connectionString = await backend.read(_connectionStringKey(connectionId));
    return (password: password, connectionString: connectionString);
  }

  static Future<void> deleteForConnection(int connectionId) async {
    await backend.delete(_passwordKey(connectionId));
    await backend.delete(_connectionStringKey(connectionId));
  }
}
