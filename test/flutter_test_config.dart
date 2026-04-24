import 'dart:async';

import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

import 'memory_secrets_backend.dart';

/// Runs before all tests in this package (see `package:test` global configuration).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ConnectionSecretsStore.backend = testMemorySecrets;
  testMemorySecrets.clear();
  await testMain();
}
