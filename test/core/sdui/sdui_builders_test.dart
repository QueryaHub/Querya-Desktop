import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/sdui/sdui_form_builder.dart';
import 'package:querya_desktop/core/sdui/sdui_form_schema.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_builder.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('SduiFormSchema', () {
    test('parses connection form JSON', () {
      final schema = SduiFormSchema.fromJson(const {
        'title': 'ClickHouse',
        'fields': [
          {
            'id': 'host',
            'type': 'text',
            'label': 'Host',
            'required': true,
            'default': 'localhost',
          },
          {'id': 'port', 'type': 'number', 'label': 'Port', 'default': 8123},
          {'id': 'password', 'type': 'password', 'label': 'Password'},
          {'id': 'ssl', 'type': 'checkbox', 'label': 'Use SSL'},
          {
            'id': 'auth',
            'type': 'select',
            'label': 'Auth',
            'options': [
              {'value': 'password', 'label': 'Password'},
              {'value': 'cert', 'label': 'Certificate'},
            ],
          },
          {'id': 'cert', 'type': 'file_picker', 'label': 'Client cert'},
        ],
      });

      expect(schema.title, 'ClickHouse');
      expect(schema.fields, hasLength(6));
      expect(schema.fields[0].type, SduiFieldType.text);
      expect(schema.fields[1].type, SduiFieldType.number);
      expect(schema.fields[2].type, SduiFieldType.password);
      expect(schema.fields[3].type, SduiFieldType.checkbox);
      expect(schema.fields[4].options, hasLength(2));
      expect(schema.fields[5].type, SduiFieldType.filePicker);
    });

    test('accepts extension-style key and boolean aliases', () {
      final schema = SduiFormSchema.fromJson(const {
        'type': 'form',
        'id': 'clickhouse_connection_form',
        'fields': [
          {
            'key': 'host',
            'label': 'Host',
            'type': 'text',
            'required': true,
            'defaultValue': 'localhost',
          },
          {
            'key': 'port',
            'label': 'Port',
            'type': 'number',
            'defaultValue': 8123,
          },
          {
            'key': 'safe_mode',
            'label': 'Safe Mode',
            'type': 'boolean',
            'defaultValue': true,
          },
        ],
      });

      expect(schema.fields, hasLength(3));
      expect(schema.fields[0].id, 'host');
      expect(schema.fields[0].defaultValue, 'localhost');
      expect(schema.fields[1].id, 'port');
      expect(schema.fields[2].id, 'safe_mode');
      expect(schema.fields[2].type, SduiFieldType.checkbox);
    });
  });

  group('SduiFormBuilder', () {
    testWidgets('validates required fields and collects values', (tester) async {
      final schema = SduiFormSchema.fromJson(const {
        'title': 'Conn',
        'fields': [
          {'id': 'host', 'type': 'text', 'label': 'Host', 'required': true},
          {'id': 'port', 'type': 'number', 'label': 'Port', 'default': 5432},
          {'id': 'password', 'type': 'password', 'label': 'Password'},
          {'id': 'ssl', 'type': 'checkbox', 'label': 'SSL', 'default': false},
        ],
      });

      final key = material.GlobalKey<SduiFormBuilderState>();
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SduiFormBuilder(key: key, schema: schema),
          ),
        ),
      );

      expect(key.currentState!.collectValues(), isNull);
      await tester.pump();
      expect(find.text('Host is required'), findsOneWidget);

      await tester.enterText(find.byType(material.TextFormField).first, 'db.local');
      await tester.pump();

      final values = key.currentState!.collectValues();
      expect(values, isNotNull);
      expect(values!['host'], 'db.local');
      expect(values['port'], 5432);
      expect(values['ssl'], isFalse);
      expect(key.currentState!.passwordFieldIds, ['password']);
    });

    testWidgets('file_picker uses injectable picker', (tester) async {
      final schema = SduiFormSchema.fromJson(const {
        'fields': [
          {'id': 'db', 'type': 'file_picker', 'label': 'Database file'},
        ],
      });
      final key = material.GlobalKey<SduiFormBuilderState>();

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SduiFormBuilder(
              key: key,
              schema: schema,
              filePicker: (_) async => '/tmp/test.db',
            ),
          ),
        ),
      );

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();

      expect(key.currentState!.snapshotValues()['db'], '/tmp/test.db');
    });
  });

  group('SduiTreeSchema', () {
    test('parses tree schema with expandable nodes', () {
      final schema = SduiTreeSchema.fromJson(const {
        'roots': [
          {
            'id': 'databases',
            'label': 'Databases',
            'expandable': true,
            'icon': 'folder',
          },
        ],
      });
      expect(schema.roots.single.id, 'databases');
      expect(schema.roots.single.expandable, isTrue);
    });

    test('maps node_type snake_case into meta nodeType', () {
      final node = SduiTreeNode.fromJson(const {
        'id': 'table.default.customers',
        'label': 'customers',
        'node_type': 'table',
        'has_children': true,
      });
      expect(node.meta['nodeType'], 'table');
      expect(node.expandable, isTrue);
    });
  });

  group('SduiTreeBuilder', () {
    testWidgets('lazy-loads children on expand', (tester) async {
      final schema = SduiTreeSchema.fromJson(const {
        'roots': [
          {
            'id': 'databases',
            'label': 'Databases',
            'expandable': true,
          },
        ],
      });

      var fetches = 0;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SduiTreeBuilder(
              schema: schema,
              fetchChildren: (id) async {
                fetches++;
                expect(id, 'databases');
                return const [
                  SduiTreeNode(id: 'db1', label: 'analytics'),
                ];
              },
            ),
          ),
        ),
      );

      expect(find.text('Databases'), findsOneWidget);
      expect(find.text('analytics'), findsNothing);

      await tester.tap(find.byIcon(QueryaIcons.expandClosed));
      await tester.pumpAndSettle();

      expect(fetches, 1);
      expect(find.text('analytics'), findsOneWidget);
    });

    testWidgets('expand chevron uses QueryaMotion tokens (Off = instant)',
        (tester) async {
      final schema = SduiTreeSchema.fromJson(const {
        'roots': [
          {
            'id': 'databases',
            'label': 'Databases',
            'expandable': true,
          },
        ],
      });

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaMotionScope(
            level: QueryaMotionLevel.off,
            child: material.Scaffold(
              body: SduiTreeBuilder(
                schema: schema,
                fetchChildren: (_) async => const [
                  SduiTreeNode(id: 'db1', label: 'analytics'),
                ],
              ),
            ),
          ),
        ),
      );

      final rotation = tester.widget<material.AnimatedRotation>(
        find.byType(material.AnimatedRotation),
      );
      expect(rotation.duration, Duration.zero);

      await tester.tap(find.byIcon(QueryaIcons.expandClosed));
      await tester.pumpAndSettle();

      expect(find.text('analytics'), findsOneWidget);
    });

    testWidgets('selects table nodes by id prefix when meta is empty',
        (tester) async {
      SduiTreeNode? selected;
      final schema = SduiTreeSchema.fromJson(const {
        'roots': [
          {
            'id': 'table.default.customers',
            'label': 'customers',
            'has_children': true,
          },
        ],
      });

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SduiTreeBuilder(
              schema: schema,
              onNodeSelected: (node) => selected = node,
            ),
          ),
        ),
      );

      await tester.tap(find.text('customers'));
      await tester.pumpAndSettle();

      expect(selected?.id, 'table.default.customers');
    });
  });
}
