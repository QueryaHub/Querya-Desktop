import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/layout_overflow.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_conn_panel_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ConnectionsPanel layout', () {
    final sizes = <String, material.Size>{
      'narrow_tall': const material.Size(320, 720),
      'very_narrow': const material.Size(280, 560),
      'medium': const material.Size(900, 640),
    };

    for (final entry in sizes.entries) {
      testWidgets('no layout overflow at ${entry.key} ${entry.value}',
          (tester) async {
        await expectNoLayoutOverflow(() async {
          await pumpWidgetWithSurfaceSize(
            tester,
            entry.value,
            ShadcnApp(
              theme: AppTheme.dark,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.dark,
              home: material.SizedBox.expand(
                child: ConnectionsPanel(
                  onPostgresOpenSqlWorkspace: (_) {},
                ),
              ),
            ),
          );
        });
      });
    }
  });
}
