import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_bar.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('SqlQueryTabSession', () {
    test('initializes with default and custom values', () {
      final session = SqlQueryTabSession(
        id: 'tab_1',
        title: 'Query 1',
        initialSql: 'SELECT 1;',
      );

      expect(session.id, 'tab_1');
      expect(session.title, 'Query 1');
      expect(session.controller.text, 'SELECT 1;');
      expect(session.running, isFalse);
      expect(session.columns, isEmpty);
      expect(session.rows, isEmpty);
      expect(session.stagingBuffer, isNull);

      session.dispose();
    });

    test('state is isolated across multiple sessions', () {
      final tab1 = SqlQueryTabSession(id: '1', title: 'Tab 1', initialSql: 'SELECT A;');
      final tab2 = SqlQueryTabSession(id: '2', title: 'Tab 2', initialSql: 'SELECT B;');

      tab1.columns = ['a'];
      tab1.rows = [['val_a']];
      tab1.statusLine = '1 row.';

      tab2.columns = ['b', 'c'];
      tab2.rows = [['val_b', 'val_c']];
      tab2.statusLine = '2 rows.';

      expect(tab1.controller.text, 'SELECT A;');
      expect(tab2.controller.text, 'SELECT B;');
      expect(tab1.columns, ['a']);
      expect(tab2.columns, ['b', 'c']);
      expect(tab1.statusLine, '1 row.');
      expect(tab2.statusLine, '2 rows.');

      tab1.dispose();
      tab2.dispose();
    });
  });

  group('SqlQueryTabBar widget', () {
    testWidgets('renders all tab titles and handles tab selection', (tester) async {
      final tab1 = SqlQueryTabSession(id: '1', title: 'Orders');
      final tab2 = SqlQueryTabSession(id: '2', title: 'Users');
      int selected = 0;
      bool addCalled = false;
      int? closedIndex;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.StatefulBuilder(
            builder: (context, setState) {
              return material.Scaffold(
                body: SqlQueryTabBar(
                  sessions: [tab1, tab2],
                  selectedIndex: selected,
                  onSelect: (i) => setState(() => selected = i),
                  onAdd: () => addCalled = true,
                  onClose: (i) => closedIndex = i,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);

      // Select second tab
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(selected, 1);

      // Add tab button
      final addBtn = find.byIcon(material.Icons.add_rounded);
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(addCalled, isTrue);

      // Close tab button
      final closeIcons = find.byIcon(material.Icons.close_rounded);
      expect(closeIcons, findsNWidgets(2));
      await tester.tap(closeIcons.last);
      await tester.pumpAndSettle();
      expect(closedIndex, 1);

      tab1.dispose();
      tab2.dispose();
    });

    testWidgets('shows unsaved tab changes dialog when closing dirty tab', (tester) async {
      final buffer = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [['1', 'Alice']],
      );
      buffer.setCell(0, 1, 'Bob');
      expect(buffer.isDirty, isTrue);

      bool? dialogResult;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) {
              return material.TextButton(
                onPressed: () async {
                  dialogResult = await showUnsavedTabChangesDialog(
                    context: context,
                    tabTitle: 'Dirty Tab',
                  );
                },
                child: const material.Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes in "Dirty Tab"'), findsOneWidget);
      expect(find.text('Discard & Close'), findsOneWidget);

      // Tap Discard & Close
      await tester.tap(find.text('Discard & Close'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      buffer.dispose();
    });
  });

  group('SqlEditorCommandBridge tab delegation', () {
    test('routes onCloseTab, onNextTab, onPrevTab correctly', () {
      final bridge = SqlEditorCommandBridge.instance;
      bridge.resetForTest();

      bool closed = false;
      bool next = false;
      bool prev = false;

      bridge.register(
        connectionId: 10,
        onNew: () {},
        onOpen: () {},
        onSave: () {},
        onCloseTab: () => closed = true,
        onNextTab: () => next = true,
        onPrevTab: () => prev = true,
      );

      expect(bridge.canCloseTab, isTrue);
      bridge.invokeCloseTab();
      expect(closed, isTrue);

      bridge.invokeNextTab();
      expect(next, isTrue);

      bridge.invokePrevTab();
      expect(prev, isTrue);

      bridge.unregister(connectionId: 10);
      expect(bridge.canCloseTab, isFalse);
    });
  });
}
