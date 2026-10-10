import 'dart:async';

import 'package:querya_desktop/app/app_wiring.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

import 'memory_secrets_backend.dart';

/// Runs before all tests in this package (see `package:test` global configuration).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Built-in commands, the extension connection picker and MCP's SQL
  // sessions, as the app installs them at startup.
  installAppWiring();
  ConnectionSecretsStore.backend = testMemorySecrets;
  testMemorySecrets.clear();
  // A connect limit is a timer; a widget test that ends with a connect pending
  // would fail on it (tests that exercise the limit pass their own).
  RedisConnection.defaultConnectTimeout = Duration.zero;
  // Avoid copying the developer's real legacy profile into test temp dirs.
  AppDataRoot.mockLegacySupportCandidates = const [];
  await testMain();
  AppDataRoot.resetMocks();
}
