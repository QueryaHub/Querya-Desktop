import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';
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

    test('postgres reads the catalog from pg_catalog, not information_schema',
        () {
      for (final sql in [
        ErdCatalog.columnsSql(SqlDialect.postgres),
        ErdCatalog.foreignKeysSql(SqlDialect.postgres),
      ]) {
        expect(sql, contains('pg_catalog.'));
        expect(sql, isNot(contains('information_schema')));
      }
      expect(ErdCatalog.foreignKeysSql(SqlDialect.postgres),
          contains('unnest(con.conkey, con.confkey)'));
    });

    test('composite foreign keys give one edge per column pair', () {
      // Recorded rows as returned for FK (a, b) -> (x, y) on PostgreSQL and
      // MySQL: one row per column pair, paired by position.
      final schema = ErdSchema.fromCatalog(
        columnRows: [
          ['parent', 'x', 'integer', '1'],
          ['parent', 'y', 'integer', '1'],
          ['child', 'id', 'integer', '1'],
          ['child', 'a', 'integer', '0'],
          ['child', 'b', 'integer', '0'],
        ],
        fkRows: [
          ['child', 'a', 'parent', 'x'],
          ['child', 'b', 'parent', 'y'],
        ],
      );
      expect(schema.relations.length, 2);
      expect(
        schema.relations.map((r) => '${r.fromColumn}->${r.toColumn}'),
        ['a->x', 'b->y'],
      );
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

  group('ErdLayout (layered)', () {
    // users <- orders <- order_items -> products, users <- sessions, lonely.
    ErdSchema shop() => ErdSchema.fromCatalog(
          columnRows: [
            ['users', 'id', 'int', '1'],
            ['users', 'email', 'text', '0'],
            ['orders', 'id', 'int', '1'],
            ['orders', 'user_id', 'int', '0'],
            ['order_items', 'id', 'int', '1'],
            ['order_items', 'order_id', 'int', '0'],
            ['order_items', 'product_id', 'int', '0'],
            ['products', 'id', 'int', '1'],
            ['sessions', 'id', 'int', '1'],
            ['sessions', 'user_id', 'int', '0'],
            ['lonely', 'id', 'int', '1'],
          ],
          fkRows: [
            ['orders', 'user_id', 'users', 'id'],
            ['order_items', 'order_id', 'orders', 'id'],
            ['order_items', 'product_id', 'products', 'id'],
            ['sessions', 'user_id', 'users', 'id'],
          ],
        );

    test('referenced tables sit left of the tables that reference them', () {
      final s = shop();
      final l = ErdLayout.compute(s);
      double x(String t) => l.positions[t]!.dx;
      expect(x('users'), lessThan(x('orders')));
      expect(x('orders'), lessThan(x('order_items')));
      expect(x('products'), lessThan(x('order_items')));
      expect(x('users'), lessThan(x('sessions')));
    });

    test('tables without relations go below the diagram', () {
      final s = shop();
      final l = ErdLayout.compute(s);
      final lonely = l.rectOf(s.tables.firstWhere((t) => t.name == 'lonely'));
      for (final t in s.tables.where((t) => t.name != 'lonely')) {
        expect(lonely.top, greaterThan(l.rectOf(t).bottom), reason: t.name);
      }
    });

    test('cards never overlap, also with a cycle and a self reference', () {
      final s = ErdSchema.fromCatalog(
        columnRows: [
          for (final t in ['a', 'b', 'c', 'd']) ...[
            [t, 'id', 'int', '1'],
            [t, 'ref', 'int', '0'],
          ],
        ],
        fkRows: [
          ['a', 'ref', 'b', 'id'],
          ['b', 'ref', 'c', 'id'],
          ['c', 'ref', 'a', 'id'],
          ['d', 'ref', 'd', 'id'],
        ],
      );
      final l = ErdLayout.compute(s);
      final rects = [for (final t in s.tables) l.rectOf(t)];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('withPosition moves one card and grows the canvas', () {
      final s = shop();
      final l = ErdLayout.compute(s);
      final moved = l.withPosition('users', const material.Offset(2000, 1500));
      expect(moved.positions['users'], const material.Offset(2000, 1500));
      expect(moved.positions['orders'], l.positions['orders']);
      expect(moved.size.width, greaterThan(2000 + ErdLayout.cardWidth));
      expect(moved.size.height, greaterThan(1500));
      expect(l.withPosition('users', const material.Offset(-50, -9)).positions['users'],
          const material.Offset(8, 8));
    });

    group('ErdRouter', () {
      void expectClean(ErdSchema s, ErdLayout l, List<ErdRoute> routes) {
        final byName = {for (final t in s.tables) t.name: t};
        final cards = [for (final t in s.tables) l.rectOf(t)];
        for (final r in routes) {
          final from = byName[r.relation.fromTable]!, to = byName[r.relation.toTable]!;
          final pts = r.points;
          final fr = l.rectOf(from), tr = l.rectOf(to);
          // Ends sit on the card sides at the column rows.
          expect(pts.first.dy, l.columnY(from, r.relation.fromColumn));
          expect([fr.left, fr.right], contains(pts.first.dx));
          expect(pts.last.dy, l.columnY(to, r.relation.toColumn));
          expect([tr.left, tr.right], contains(pts.last.dx));
          for (var i = 0; i + 1 < pts.length; i++) {
            final a = pts[i], b = pts[i + 1];
            expect(a.dx == b.dx || a.dy == b.dy, isTrue,
                reason: 'orthogonal segment $a -> $b');
            for (var k = 1; k < 10; k++) {
              final p = material.Offset.lerp(a, b, k / 10)!;
              for (final c in cards) {
                final inside = p.dx > c.left + 0.5 &&
                    p.dx < c.right - 0.5 &&
                    p.dy > c.top + 0.5 &&
                    p.dy < c.bottom - 0.5;
                expect(inside, isFalse,
                    reason: '${r.relation.fromTable}->${r.relation.toTable} crosses $c');
              }
            }
          }
        }
      }

      test('every relation is routed around the cards', () {
        final s = shop();
        final l = ErdLayout.compute(s);
        final routes = ErdRouter.route(s, l);
        expect(routes, hasLength(4));
        expectClean(s, l, routes);
      });

      test('a card placed in the way is avoided', () {
        final s = ErdSchema.fromCatalog(
          columnRows: [
            ['users', 'id', 'int', '1'],
            ['orders', 'user_id', 'int', '0'],
            ['blocker', 'id', 'int', '1'],
            ['blocker', 'a', 'int', '0'],
            ['blocker', 'b', 'int', '0'],
          ],
          fkRows: [
            ['orders', 'user_id', 'users', 'id'],
          ],
        );
        final l = ErdLayout.compute(s)
            .withPosition('users', const material.Offset(40, 100))
            .withPosition('blocker', const material.Offset(400, 80))
            .withPosition('orders', const material.Offset(760, 100));
        final routes = ErdRouter.route(s, l);
        expectClean(s, l, routes);
        expect(routes.single.points.length, greaterThan(2),
            reason: 'must bend around the blocker');
      });

      test('parallel segments of different edges do not overlap', () {
        final s = shop();
        final routes = ErdRouter.route(s, ErdLayout.compute(s));
        final segs = <(int, material.Offset, material.Offset)>[];
        for (var r = 0; r < routes.length; r++) {
          final p = routes[r].points;
          for (var i = 1; i + 2 < p.length; i++) {
            segs.add((r, p[i], p[i + 1]));
          }
        }
        for (var i = 0; i < segs.length; i++) {
          for (var j = i + 1; j < segs.length; j++) {
            final (ra, a1, a2) = segs[i];
            final (rb, b1, b2) = segs[j];
            if (ra == rb) continue;
            if (a1.dx == a2.dx && b1.dx == b2.dx && a1.dx == b1.dx) {
              final lo = [a1.dy, a2.dy].reduce((x, y) => x < y ? x : y);
              final hi = [a1.dy, a2.dy].reduce((x, y) => x > y ? x : y);
              final lo2 = [b1.dy, b2.dy].reduce((x, y) => x < y ? x : y);
              final hi2 = [b1.dy, b2.dy].reduce((x, y) => x > y ? x : y);
              expect(lo < hi2 - 0.5 && lo2 < hi - 0.5, isFalse,
                  reason: 'vertical overlap at x=${a1.dx}');
            }
          }
        }
      });

      test('no relations means no routes', () {
        final s = ErdSchema.fromCatalog(columnRows: [
          ['a', 'id', 'int', '1'],
        ], fkRows: const []);
        expect(ErdRouter.route(s, ErdLayout.compute(s)), isEmpty);
      });
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

    test('png ratio keeps the longest side within 8192 px', () {
      final ratio = ErdExport.pngPixelRatio(const material.Size(20000, 9000));
      expect((20000 * ratio).round(), lessThanOrEqualTo(8192));
      expect(ratio, lessThan(1));
      expect(
          ErdExport.pngPixelRatio(const material.Size(800, 600)), 2);
    });

    test('svg draws both end markers, rounded routes and PK/FK pills', () {
      final s = sample();
      final layout = ErdLayout.compute(s);
      final svg = ErdExport.toSvg(s, layout);
      // The orders.user_id -> users.id relation: a crow's foot and a bar.
      expect(svg, contains('<title>orders.user_id'));
      expect(svg, contains(' Q '));
      expect(svg, contains('>PK<'));
      expect(svg, contains('>FK<'));
      expect(svg, contains('clip-path="url(#card0)"'));
    });

    test('svg fits long types inside the card with an ellipsis', () {
      const longType = "enum('pending','paid','shipped','cancelled','refunded')";
      final s = ErdSchema.fromCatalog(columnRows: [
        ['orders', 'status', longType, '0'],
      ], fkRows: const []);
      final svg = ErdExport.toSvg(s, ErdLayout.compute(s));
      expect(svg, isNot(contains(longType)));
      expect(svg, contains('…'));
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
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
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
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('a card can be dragged and Auto layout puts it back',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(delegate: delegate(), dialect: SqlDialect.sqlite),
      ));
      await t.pump();
      await t.pump();
      final card = find.byKey(const material.ValueKey('erd_table_orders'));
      final users = find.byKey(const material.ValueKey('erd_table_users'));
      final before = t.getTopLeft(card);
      final usersBefore = t.getTopLeft(users);

      await t.drag(card, const material.Offset(120, 60));
      await t.pump();
      final after = t.getTopLeft(card);
      expect(after.dx - before.dx, greaterThan(100));
      expect(after.dy - before.dy, greaterThan(40));
      // The other card stayed: the drag moved the card, not the canvas.
      expect(t.getTopLeft(users), usersBefore);

      await t.tap(find.byKey(const material.ValueKey('erd_auto_layout')));
      await t.pump();
      expect(t.getTopLeft(card), before);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('long types do not overflow and PK+FK shows both markers',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      final junction = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(rows: [
            ['orders', 'id', 'INTEGER', '1'],
            ['order_items', 'order_id', 'INTEGER', '1'],
            ['order_items', 'status', "enum('pending','paid','shipped','cancelled')", '0'],
            ['order_items', 'created_at', 'timestamp with time zone', '0'],
          ]);
        }
        return const SqlExecutionResult(rows: [
          ['order_items', 'order_id', 'orders', 'id'],
        ]);
      });
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(delegate: junction, dialect: SqlDialect.sqlite),
      ));
      await t.pump();
      await t.pump();

      final card = find.byKey(const material.ValueKey('erd_table_order_items'));
      expect(card, findsOneWidget);
      expect(t.takeException(), isNull);
      expect(
        find.descendant(
            of: card, matching: find.byIcon(material.Icons.key_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: card, matching: find.byIcon(material.Icons.link_rounded)),
        findsOneWidget,
      );
    });

    /// users <- orders; lonely has no relation.
    FakeSqlExecutionDelegate threeTables() =>
        FakeSqlExecutionDelegate(onExecute: (sql) {
          if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
            return const SqlExecutionResult(rows: [
              ['users', 'id', 'INTEGER', '1'],
              ['orders', 'id', 'INTEGER', '1'],
              ['orders', 'user_id', 'INTEGER', '0'],
              ['lonely', 'id', 'INTEGER', '1'],
            ]);
          }
          return const SqlExecutionResult(rows: [
            ['orders', 'user_id', 'users', 'id'],
          ]);
        });

    Iterable<double> opacityOf(WidgetTester t, String table) =>
        t.widgetList<material.Opacity>(find.ancestor(
          of: find.byKey(material.ValueKey('erd_table_$table')),
          matching: find.byType(material.Opacity),
        )).map((o) => o.opacity);

    testWidgets('zoom buttons change the zoom label', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(delegate: delegate(), dialect: SqlDialect.sqlite),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('100%'), findsOneWidget);

      await t.tap(find.byKey(const material.ValueKey('erd_zoom_out')));
      await t.pump();
      expect(find.text('80%'), findsOneWidget);

      await t.tap(find.byKey(const material.ValueKey('erd_zoom_in')));
      await t.pump();
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('a click picks a table and fades the unrelated ones',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(delegate: threeTables(), dialect: SqlDialect.sqlite),
      ));
      await t.pump();
      await t.pump();

      await t.tap(find.byKey(const material.ValueKey('erd_table_lonely')));
      // A tap waits out the double-tap window.
      await t.pump(const Duration(milliseconds: 400));
      expect(opacityOf(t, 'users'), contains(0.35));
      expect(opacityOf(t, 'lonely'), isNot(contains(0.35)));

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(opacityOf(t, 'users'), isNot(contains(0.35)));
    });

    testWidgets('search lists matches and a tap picks the table',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(delegate: threeTables(), dialect: SqlDialect.sqlite),
      ));
      await t.pump();
      await t.pump();

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyF);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      await t.pump();

      await t.enterText(find.byType(material.EditableText), 'ord');
      await t.pump();
      expect(find.byKey(const material.ValueKey('erd_search_result_orders')),
          findsOneWidget);
      expect(find.byKey(const material.ValueKey('erd_search_result_lonely')),
          findsNothing);

      await t.tap(find.byKey(const material.ValueKey('erd_search_result_orders')));
      await t.pump(const Duration(milliseconds: 400));
      expect(opacityOf(t, 'lonely'), contains(0.35));
      expect(opacityOf(t, 'orders'), isNot(contains(0.35)));
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
