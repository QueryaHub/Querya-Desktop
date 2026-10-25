import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/team/team_profile.dart';

import '../../memory_secrets_backend.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;
}

/// `importInto` tries every row: a row the keyring refuses is counted and
/// reported, the others are saved (#1759).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_team_import_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    testMemorySecrets.clear();
    for (final c in await LocalDb.instance.getConnections()) {
      if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
    }
  });

  ConnectionRow row(String name) => ConnectionRow(
        type: 'postgresql',
        name: name,
        host: 'db.example.com',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
      );

  Future<List<String>> savedNames() async => [
        for (final c in await LocalDb.instance.getConnections()) c.name,
      ]..sort();

  test('all rows are saved when the keyring answers', () async {
    final result = await TeamProfileCodec.importInto(
      LocalDb.instance,
      [row('A'), row('B'), row('C')],
    );

    expect(result.added, 3);
    expect(result.failed, 0);
    expect(result.firstError, isNull);
    expect(await savedNames(), ['A', 'B', 'C']);
  });

  test(
      'a refusal on the middle row does not stop the rest, and is counted '
      'with its error', () async {
    // Each row writes two secrets: A is writes 1-2, B starts at write 3.
    final error = StateError('keyring refused B');
    testMemorySecrets.failOnCall(SecretsOp.write, 3, error);

    final result = await TeamProfileCodec.importInto(
      LocalDb.instance,
      [row('A'), row('B'), row('C')],
    );

    expect(result.added, 2);
    expect(result.failed, 1);
    expect(result.firstError, same(error));
    expect(await savedNames(), ['A', 'C']);
  });

  test('when every row fails, the first error is kept and nothing is saved',
      () async {
    final first = StateError('first');
    testMemorySecrets.failOnCall(SecretsOp.write, 1, first);
    testMemorySecrets.failOnCall(SecretsOp.write, 2, StateError('second'));

    final result = await TeamProfileCodec.importInto(
      LocalDb.instance,
      [row('A'), row('B')],
    );

    expect(result.added, 0);
    expect(result.failed, 2);
    expect(result.firstError, same(first));
    expect(await savedNames(), isEmpty);
  });

  test('a row that already exists is skipped, not counted as failed', () async {
    await LocalDb.instance.addConnection(row('A'));

    final result = await TeamProfileCodec.importInto(
      LocalDb.instance,
      [row('A'), row('B')],
    );

    expect(result.added, 1);
    expect(result.failed, 0);
  });
}
