import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  @override
  Future<String?> getApplicationCachePath() async => _root;
  @override
  Future<String?> getLibraryPath() async => _root;
  @override
  Future<String?> getExternalStoragePath() async => _root;
  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];
  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      [_root];
  @override
  Future<String?> getDownloadsPath() async => _root;
}

/// #1007: the built tab pane is cached (`_paneCache`) to skip rebuilding
/// untouched tabs on tab-switch, but the cached pane's Save button closes
/// over `widget.isReadOnly` at build time. If a connection's read-only lock
/// flips on while a tab with unsaved staged edits is already open and
/// cached, Save must not keep working just because that tab hasn't been
/// rebuilt for any other reason since.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir =
        await Directory.systemTemp.createTemp('querya_sql_readonly_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
      'Save Changes becomes disabled in an already-open dirty tab once the connection turns read-only',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));

    const conn = ConnectionRow(
      id: 504,
      type: 'sqlite',
      name: 'Test SQLite',
      host: ':memory:',
      createdAt: '2026-09-24T00:00:00Z',
    );

    material.Widget buildWorkspace({required bool isReadOnly}) {
      return queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: SqliteSqlWorkspace(
            connectionRow: conn,
            isReadOnly: isReadOnly,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWorkspace(isReadOnly: false));
    await tester.pumpAndSettle();

    final workspaceState = tester.state(find.byType(SqliteSqlWorkspace));
    final dynamic dynamicState = workspaceState;
    final activeSession = dynamicState.activeSession;
    expect(activeSession, isNotNull);

    // Simulate a query having just run and produced an editable result,
    // exactly as `_execute` would set it up, without needing a live
    // connection: a result with a detected primary key and a dirty edit.
    activeSession.lastExecutedSql = 'SELECT * FROM users;';
    activeSession.columns = ['id', 'name'];
    activeSession.rows = [
      ['1', 'Alice'],
    ];
    activeSession.resultGridPrimaryKeys = ['id'];
    final buffer = DataGridStagingBuffer(
      columns: ['id', 'name'],
      rows: [
        ['1', 'Alice'],
      ],
      primaryKeys: ['id'],
    );
    activeSession.stagingBuffer = buffer;
    buffer.setCell(0, 1, 'Bob');
    expect(buffer.isDirty, isTrue);

    dynamicState.debugRebuildActivePane();
    await tester.pumpAndSettle();

    final saveButtonFinder = find.widgetWithText(PrimaryButton, 'Save Changes');
    expect(saveButtonFinder, findsOneWidget);
    expect(
      tester.widget<PrimaryButton>(saveButtonFinder).onPressed,
      isNotNull,
      reason: 'Save should be enabled while writable and dirty',
    );

    // The connection becomes read-only while this dirty tab is still open
    // and its pane is cached — Save must disable immediately, not only the
    // next time this tab happens to rebuild for some other reason.
    await tester.pumpWidget(buildWorkspace(isReadOnly: true));
    await tester.pumpAndSettle();

    final saveButtonAfter = find.widgetWithText(PrimaryButton, 'Save Changes');
    expect(saveButtonAfter, findsOneWidget);
    expect(
      tester.widget<PrimaryButton>(saveButtonAfter).onPressed,
      isNull,
      reason:
          'Save must disable once the connection is read-only, even though '
          'this tab was already open and cached before the lock changed',
    );
    expect(buffer.isDirty, isTrue,
        reason: 'toggling read-only must not touch the staged edits');

    material.FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const material.SizedBox());
    await tester.pumpAndSettle();
  });
}
