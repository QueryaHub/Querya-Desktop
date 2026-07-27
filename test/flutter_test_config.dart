import 'dart:async';

import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

import 'memory_secrets_backend.dart';

/// Runs before all tests in this package (see `package:test` global configuration).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ConnectionSecretsStore.backend = testMemorySecrets;
  testMemorySecrets.clear();
  // Avoid copying the developer's real legacy profile into test temp dirs.
  AppDataRoot.mockLegacySupportCandidates = const [];
  await testMain();
  AppDataRoot.resetMocks();
}
