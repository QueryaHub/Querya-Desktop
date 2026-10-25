import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';

import '../../memory_secrets_backend.dart';
import '../../support/querya_theme_test_shell.dart';

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

const _row = ConnectionRow(
  type: 'postgres',
  name: 'Save flow',
  host: 'localhost',
  port: 5432,
  username: 'admin',
  password: 'secret',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_save_new_conn_');
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

  Future<material.BuildContext> pumpHost(WidgetTester tester) async {
    late material.BuildContext host;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) {
            host = context;
            return const material.SizedBox();
          },
        ),
      ),
    );
    return host;
  }

  Future<List<ConnectionRow>> savedRows(WidgetTester tester) async =>
      (await tester.runAsync(() => LocalDb.instance.getConnections()))!
          .where((c) => c.name == _row.name)
          .toList();

  testWidgets('a stored connection returns true and shows no toast',
      (tester) async {
    final host = await pumpHost(tester);

    final saved = await tester.runAsync(() => saveNewConnection(host, _row));
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isTrue);
    expect(await savedRows(tester), hasLength(1));
    expect(find.textContaining('was not saved'), findsNothing);
  });

  testWidgets(
      'a failed secret write returns false, rolls the row back and says so',
      (tester) async {
    final host = await pumpHost(tester);
    testMemorySecrets.failNextWrite = StateError('keychain write failed');

    final saved = await tester.runAsync(() => saveNewConnection(host, _row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isFalse);
    expect(await savedRows(tester), isEmpty);
    expect(
      find.textContaining(
        'The connection was not saved. Bad state: keychain write failed',
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'a save that fails on the second secret leaves nothing behind, and the '
      'same row saves once the keyring answers', (tester) async {
    final host = await pumpHost(tester);
    testMemorySecrets.failOnCall(
      SecretsOp.write,
      2,
      StateError('connection string refused'),
    );
    final withString = _row.copyWith(connectionString: 'postgres://x@y/z');

    final first =
        await tester.runAsync(() => saveNewConnection(host, withString));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(first, isFalse);
    expect(await savedRows(tester), isEmpty);
    expect(testMemorySecrets.keys, isEmpty);
    expect(find.textContaining('was not saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final second =
        await tester.runAsync(() => saveNewConnection(host, withString));
    await tester.pump(const Duration(milliseconds: 400));

    expect(second, isTrue);
    expect(await savedRows(tester), hasLength(1));
    expect(find.textContaining('was not saved'), findsNothing);
  });
}
