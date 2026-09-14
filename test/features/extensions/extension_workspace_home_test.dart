import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_workspace_home.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  final extConn = ConnectionRow(
    id: 10,
    name: 'ClickHouse Analytics',
    type: 'clickhouse',
    host: 'clickhouse.internal',
    port: 8123,
    extensionId: 'clickhouse-driver',
    createdAt: DateTime.now().toIso8601String(),
  );

  testWidgets('ExtensionWorkspaceHome renders QueryaTabStrip with Overview and SQL',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: ExtensionWorkspaceHome(
              connectionRow: extConn,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ClickHouse Analytics'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('SQL'), findsWidgets);
  });

  testWidgets('ExtensionWorkspaceHome renders Return to button when last selected object is set',
      (tester) async {
    var restored = false;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: ExtensionWorkspaceHome(
              connectionRow: extConn,
              lastSelectedExtensionObject: (database: 'default', name: 'events_v1'),
              onRestoreLastSelectedObject: () => restored = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Return to events_v1'), findsOneWidget);

    await tester.tap(find.text('Return to events_v1'));
    expect(restored, isTrue);
  });
}
