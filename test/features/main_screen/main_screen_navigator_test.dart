import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/features/main_screen/main_screen_navigator.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';

const _sqlite = ConnectionRow(type: 'sqlite', name: 'local', createdAt: '2026-10-18');
const _mongo = ConnectionRow(type: 'mongodb', name: 'docs', createdAt: '2026-10-18');

void main() {
  late ValueNotifier<MainScreenWorkspaceState> workspace;
  late MainScreenNavigator nav;
  var pendingChanges = 0;

  Future<void> pumpNavigator(WidgetTester tester) async {
    workspace = ValueNotifier(MainScreenWorkspaceState.empty);
    pendingChanges = 0;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    ));
    nav = MainScreenNavigator(
      workspace: workspace,
      context: () => context,
      mounted: () => true,
      onPendingMongoCollectionChanged: () => pendingChanges++,
    );
  }

  testWidgets('a Mongo collection pick is pending until another connection',
      (tester) async {
    await pumpNavigator(tester);
    await nav.selectMongoCollection(_mongo, 'app', 'users');
    expect(workspace.value.selectedMongoCollection, 'users');
    expect(nav.pendingMongoCollection, 'users');
    expect(pendingChanges, 1);

    // The same pick again changes nothing and does not notify.
    await nav.selectMongoCollection(_mongo, 'app', 'users');
    expect(pendingChanges, 1);

    await nav.selectMongoDatabase(_mongo, 'app');
    expect(nav.pendingMongoCollection, isNull);
    expect(workspace.value.selectedMongoCollection, isNull);
  });

  testWidgets('picking the object that is open does nothing', (tester) async {
    await pumpNavigator(tester);
    await nav.selectSqliteObject(_sqlite, 'users', SqliteObjectKind.table);
    final first = workspace.value;
    expect(first.selectedSqliteObject?.name, 'users');
    await nav.selectSqliteObject(_sqlite, 'users', SqliteObjectKind.table);
    expect(identical(workspace.value, first), isTrue);
  });

  testWidgets('Redis picks keep the database and skip the repeat',
      (tester) async {
    await pumpNavigator(tester);
    const redis = ConnectionRow(type: 'redis', name: 'cache', createdAt: '2026-10-18');
    await nav.selectRedisDatabase(redis, 3);
    expect(workspace.value.activeRedisDb, 3);
    final first = workspace.value;
    await nav.selectRedisDatabase(redis, 3);
    expect(identical(workspace.value, first), isTrue);
  });

  testWidgets('home empties the workspace, close keeps the connection',
      (tester) async {
    await pumpNavigator(tester);
    await nav.selectSqliteObject(_sqlite, 'users', SqliteObjectKind.table);
    expect(nav.hasCloseableWorkspace(workspace.value), isTrue);

    await nav.closeWorkspace();
    expect(workspace.value.selectedSqliteObject, isNull);
    expect(workspace.value.activeConnection?.name, 'local');
    expect(nav.hasCloseableWorkspace(workspace.value), isFalse);

    await nav.goHome();
    expect(workspace.value.activeConnection, isNull);
  });
}
