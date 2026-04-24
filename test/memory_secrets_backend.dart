import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

/// Shared in-memory backend wired from `test/flutter_test_config.dart`.
final MemorySecretsStorageBackend testMemorySecrets = MemorySecretsStorageBackend();

/// In-memory secrets backend for `flutter test` (no OS keychain / libsecret).
class MemorySecretsStorageBackend implements SecretsStorageBackend {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  void clear() => _values.clear();
}
