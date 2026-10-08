import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

ErdSchema sample() => ErdSchema.fromCatalog(
      columnRows: [
        ['users', 'id', 'integer', '1'],
        ['users', 'name', 'text', '0'],
        ['orders', 'id', 'integer', 't'],
        ['orders', 'user_id', 'integer', '0'],
        ['lonely', 'id', 'integer', '1'],
      ],
      fkRows: [
        ['orders', 'user_id', 'users', 'id'],
        ['orders', 'x', 'ghost', 'id'],
      ],
    );

void main() {
  group('ErdSchema.fromCatalog', () {
    test('marks PK/FK and drops relations to unknown tables', () {
      final s = sample();
      expect(s.tables.map((t) => t.name), ['users', 'orders', 'lonely']);
      expect(s.relations.length, 1);
      final orders = s.tables[1];
      expect(orders.columns[0].isPrimaryKey, isTrue);
      expect(orders.columns[1].isForeignKey, isTrue);
      expect(s.tables[0].columns[1].isForeignKey, isFalse);
    });
  });

  group('ErdCatalog', () {
    test('has queries for every dialect', () {
      for (final d in SqlDialect.values) {
        expect(ErdCatalog.columnsSql(d), contains('SELECT'));
        expect(ErdCatalog.foreignKeysSql(d), contains('SELECT'));
      }
    });

    test('load runs both queries through the delegate', () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(rows: [
            ['a', 'id', 'INTEGER', '1'],
          ]);
        }
        return const SqlExecutionResult();
      });
      final schema = await ErdCatalog.load(delegate, SqlDialect.sqlite);
      expect(delegate.executed.length, 2);
      expect(schema.tables.single.name, 'a');
    });
  });

  group('ErdLayout', () {
    test('places every table without overlap', () {
      final s = sample();
      final l = ErdLayout.compute(s);
      expect(l.positions.length, 3);
      final rects = [for (final t in s.tables) l.rectOf(t)];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
        expect(l.size.width, greaterThanOrEqualTo(rects[i].right));
        expect(l.size.height, greaterThanOrEqualTo(rects[i].bottom));
      }
    });
  });

  group('ErdExport', () {
    test('mermaid contains tables, keys and relation', () {
      final m = ErdExport.toMermaid(sample());
      expect(m, startsWith('erDiagram'));
      expect(m, contains('users {'));
      expect(m, contains('integer id PK'));
      expect(m, contains('integer user_id FK'));
      expect(m, contains('users ||--o{ orders : "user_id"'));
    });

    test('mermaid sanitizes odd identifiers', () {
      final s = ErdSchema.fromCatalog(columnRows: [
        ['my table', 'a-b', 'character varying(10)', '0'],
      ], fkRows: const []);
      final m = ErdExport.toMermaid(s);
      expect(m, contains('my_table {'));
      expect(m, contains('character_varying_10_ a_b'));
    });

    test('svg is well formed and escapes names', () {
      final s = ErdSchema.fromCatalog(columnRows: [
        ['t<1>', 'id', 'int', '1'],
      ], fkRows: const []);
      final svg = ErdExport.toSvg(s, ErdLayout.compute(s));
      expect(svg, startsWith('<svg'));
      expect(svg, contains('t&lt;1&gt;'));
      expect(svg.trim(), endsWith('</svg>'));
    });
  });

  group('ErdView', () {
    FakeSqlExecutionDelegate delegate() =>
        FakeSqlExecutionDelegate(onExecute: (sql) {
          if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
            return const SqlExecutionResult(rows: [
              ['users', 'id', 'INTEGER', '1'],
              ['orders', 'user_id', 'INTEGER', '0'],
            ]);
          }
          return const SqlExecutionResult(rows: [
            ['orders', 'user_id', 'users', 'id'],
          ]);
        });

    testWidgets('renders cards, opens table and exports', (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 800));
      String? opened;
      final saved = <String, Uint8List>{};
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          delegate: delegate(),
          dialect: SqlDialect.sqlite,
          onOpenTable: (n) => opened = n,
          onSaveFile: (n, b) async => saved[n] = b,
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.byKey(const material.ValueKey('erd_table_users')),
          findsOneWidget);
      expect(find.byKey(const material.ValueKey('erd_table_orders')),
          findsOneWidget);

      await t.tap(find.byKey(const material.ValueKey('erd_mermaid')));
      await t.pump();
      expect(utf8.decode(saved['diagram.mmd']!), contains('erDiagram'));

      await t.tap(find.byKey(const material.ValueKey('erd_svg')));
      await t.pump();
      expect(utf8.decode(saved['diagram.svg']!), contains('<svg'));

      final card = find.byKey(const material.ValueKey('erd_table_users'));
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(card);
      await t.pump();
      expect(opened, 'users');
    });

    testWidgets('shows empty state', (t) async {
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          delegate: FakeSqlExecutionDelegate(
              onExecute: (_) => const SqlExecutionResult()),
          dialect: SqlDialect.postgres,
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('No tables found'), findsOneWidget);
    });
  });
}
