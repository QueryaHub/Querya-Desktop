import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_bar.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';

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

    test('tracks text modifications and markSaved updates', () {
      final session = SqlQueryTabSession(
        id: 'tab_file',
        title: 'File Tab',
        initialSql: 'SELECT 1;',
        filePath: '/tmp/test.sql',
      );

      expect(session.isModified, isFalse);
      expect(session.isDirty, isFalse);

      // Typing new text marks modified & dirty
      session.controller.text = 'SELECT 1;\nSELECT 2;';
      expect(session.isModified, isTrue);
      expect(session.isDirty, isTrue);

      // Typing back to initial text resets modified & dirty
      session.controller.text = 'SELECT 1;';
      expect(session.isModified, isFalse);
      expect(session.isDirty, isFalse);

      // Mutate and save
      session.controller.text = 'SELECT * FROM users;';
      expect(session.isModified, isTrue);
      session.markSaved(newFilePath: '/tmp/users.sql');
      expect(session.isModified, isFalse);
      expect(session.isDirty, isFalse);
      expect(session.filePath, '/tmp/users.sql');

      session.dispose();
    });

    test('unsaved draft query without filePath is treated as dirty', () {
      final session = SqlQueryTabSession(
        id: 'tab_draft',
        title: 'Draft Tab',
      );

      expect(session.isModified, isFalse);
      expect(session.isDirty, isFalse);

      session.controller.text = 'SELECT 42;';
      expect(session.isDirty, isTrue);

      session.controller.text = '   ';
      expect(session.isDirty, isFalse);

      session.dispose();
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

    testWidgets('actions sit right of the tabs and leave them their width (#1558)',
        (tester) async {
      final tab = SqlQueryTabSession(id: '1', title: 'Orders');
      double? seenMaxWidth;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 600,
              child: SqlQueryTabBar(
                sessions: [tab],
                selectedIndex: 0,
                onSelect: (_) {},
                onAdd: () {},
                actions: material.LayoutBuilder(
                  builder: (context, constraints) {
                    seenMaxWidth = constraints.maxWidth;
                    return const material.SizedBox(
                      key: material.ValueKey('wide_actions'),
                      width: 900,
                      height: 32,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 600 less the strip padding, the gap and the width kept for the tabs.
      expect(seenMaxWidth, lessThanOrEqualTo(600 - SqlQueryTabBar.minTabsWidth));
      final actions = tester.getRect(find.byKey(const material.ValueKey('wide_actions')));
      final tabs = tester.getRect(find.text('Orders'));
      expect(actions.left, greaterThanOrEqualTo(tabs.right));

      tab.dispose();
    });

    testWidgets('QueryaTabStrip.naturalWidth is what the strip really takes',
        (tester) async {
      final titles = ['Query 1', 'Orders by day', 'x'];
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.Align(
              alignment: material.Alignment.topLeft,
              child: material.SizedBox(
                width: 1200,
                child: QueryaTabStrip(
                  labels: titles,
                  selectedIndex: 1,
                  onSelected: (_) {},
                  onAdd: () {},
                  onClose: (_) {},
                  canClose: (_) => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final strip = tester.getRect(find.byType(QueryaTabStrip));
      final add = tester.getRect(
          find.byKey(const material.ValueKey('querya_tab_add_button')));
      // The widest case: the selected tab is the one measured at w600, and the
      // others are narrower, so the estimate is never short.
      final real = add.right - strip.left;
      final natural = QueryaTabStrip.naturalWidth(titles, closable: true);
      expect(natural, greaterThanOrEqualTo(real - 0.5));
      expect(natural, lessThan(real + 12 * titles.length));
    });

    testWidgets('wide actions never push the add button out of reach (#1558)',
        (tester) async {
      final tabs = [
        for (var i = 1; i <= 3; i++)
          SqlQueryTabSession(id: '$i', title: 'Query $i'),
      ];
      var added = 0;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 800,
              child: SqlQueryTabBar(
                sessions: tabs,
                selectedIndex: 0,
                onSelect: (_) {},
                onAdd: () => added++,
                actions: const material.SizedBox(width: 900, height: 32),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const material.ValueKey('querya_tab_add_button')));
      expect(added, 1);

      for (final t in tabs) {
        t.dispose();
      }
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

    testWidgets('shows custom message in unsaved tab changes dialog', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) {
              return material.TextButton(
                onPressed: () {
                  showUnsavedTabChangesDialog(
                    context: context,
                    tabTitle: 'Query 1',
                    message: 'Custom query text warning',
                  );
                },
                child: const material.Text('Open Custom Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Custom Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes in "Query 1"'), findsOneWidget);
      expect(find.text('Custom query text warning'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
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
