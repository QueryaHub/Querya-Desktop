import 'dart:convert';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_geometry.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_router.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
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
        // Schema names may still mention information_schema to exclude it.
        expect(sql, isNot(contains('information_schema.')));
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

    test('every dialect reads column nullability', () {
      expect(ErdCatalog.columnsSql(SqlDialect.postgres), contains('attnotnull'));
      expect(ErdCatalog.columnsSql(SqlDialect.mysql), contains('is_nullable'));
      expect(ErdCatalog.columnsSql(SqlDialect.sqlite), contains('"notnull"'));
    });

    test('a nullable foreign key is an optional relation', () {
      final s = ErdSchema.fromCatalog(columnRows: [
        ['users', 'id', 'int', '1', '0'],
        ['orders', 'id', 'int', '1', '0'],
        ['orders', 'customer_id', 'int', '0', '1'],
        ['orders', 'user_id', 'int', '0', '0'],
      ], fkRows: [
        ['orders', 'customer_id', 'users', 'id'],
        ['orders', 'user_id', 'users', 'id'],
      ]);
      final optional = {
        for (final r in s.relations) r.fromColumn: r.optional,
      };
      expect(optional, {'customer_id': true, 'user_id': false});
      expect(s.tables[1].columns[1].isNullable, isTrue);
    });

    test('postgres names tables of other schemas schema.table', () {
      expect(ErdCatalog.foreignKeysSql(SqlDialect.postgres),
          contains("|| '.' ||"));
      expect(ErdCatalog.columnsSql(SqlDialect.postgres, schema: 'sales'),
          contains("nspname = 'sales'"));
    });

    test('neighbourhood follows foreign keys up to the requested depth', () {
      final fks = [
        ['b', 'a_id', 'a', 'id'],
        ['c', 'b_id', 'b', 'id'],
        ['d', 'x', 'z', 'id'],
      ];
      expect(ErdCatalog.neighbourhood(fks, 'a', 1), {'a', 'b'});
      expect(ErdCatalog.neighbourhood(fks, 'a', 2), {'a', 'b', 'c'});
      expect(ErdCatalog.neighbourhood(fks, 'z', 5), {'z', 'd'});
    });

    test('cycles and self references end the walk', () {
      final fks = [
        ['a', 'b_id', 'b', 'id'],
        ['b', 'a_id', 'a', 'id'],
        ['a', 'parent', 'a', 'id'],
      ];
      expect(ErdCatalog.neighbourhood(fks, 'a', 9), {'a', 'b'});
    });

    test('a table without relations is its own neighbourhood', () {
      expect(ErdCatalog.neighbourhood(const [], 'lonely', 2), {'lonely'});
    });

    test('loadNeighbourhood loads only the tables around the one asked for',
        () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(rows: [
            ['a', 'id', 'INTEGER', '1'],
            ['b', 'id', 'INTEGER', '1'],
            ['b', 'a_id', 'INTEGER', '0'],
            ['c', 'id', 'INTEGER', '1'],
          ]);
        }
        if (sql == ErdCatalog.foreignKeysSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(rows: [
            ['b', 'a_id', 'a', 'id'],
          ]);
        }
        return const SqlExecutionResult();
      });
      final s = await ErdCatalog.loadNeighbourhood(
        delegate,
        SqlDialect.sqlite,
        table: 'a',
      );
      expect(s.tables.map((t) => t.name), ['a', 'b']);
      expect(s.relations.length, 1);
    });

    test('a PostgreSQL table of the current schema is found by its bare name',
        () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.foreignKeysSql(SqlDialect.postgres)) {
          return const SqlExecutionResult(rows: [
            ['orders', 'user_id', 'users', 'id'],
            ['users', 'org_id', 'orgs', 'id'],
          ]);
        }
        if (sql == ErdCatalog.columnsSql(SqlDialect.postgres)) {
          return const SqlExecutionResult(rows: [
            ['users', 'id', 'integer', '1'],
            ['users', 'org_id', 'integer', '0'],
            ['orders', 'id', 'integer', '1'],
            ['orders', 'user_id', 'integer', '0'],
            ['orgs', 'id', 'integer', '1'],
            ['unrelated', 'id', 'integer', '1'],
          ]);
        }
        return const SqlExecutionResult();
      });
      // The table browser names it `public.users`; the catalog says `users`.
      final s = await ErdCatalog.loadNeighbourhood(
        delegate,
        SqlDialect.postgres,
        table: 'public.users',
      );
      expect(s.tables.map((t) => t.name).toSet(), {'users', 'orders', 'orgs'});
      expect(s.relations, hasLength(2));
    });

    test('a PostgreSQL table with no keys is found by its columns', () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.postgres, schema: 'public')) {
          return const SqlExecutionResult(rows: [
            ['lonely', 'id', 'integer', '1'],
            ['other', 'id', 'integer', '1'],
          ]);
        }
        return const SqlExecutionResult();
      });
      final s = await ErdCatalog.loadNeighbourhood(
        delegate,
        SqlDialect.postgres,
        table: 'public.lonely',
      );
      expect(s.tables.map((t) => t.name), ['lonely']);
      expect(s.relations, isEmpty);
    });

    test('a PostgreSQL table of another schema keeps its qualified name',
        () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.foreignKeysSql(SqlDialect.postgres)) {
          return const SqlExecutionResult(rows: [
            ['sales.orders', 'customer_id', 'customers', 'id'],
          ]);
        }
        if (sql == ErdCatalog.columnsSql(SqlDialect.postgres, schema: 'sales')) {
          return const SqlExecutionResult(rows: [
            ['sales.orders', 'id', 'integer', '1'],
            ['sales.orders', 'customer_id', 'integer', '0'],
          ]);
        }
        if (sql == ErdCatalog.columnsSql(SqlDialect.postgres)) {
          return const SqlExecutionResult(rows: [
            ['customers', 'id', 'integer', '1'],
            ['users', 'id', 'integer', '1'],
          ]);
        }
        return const SqlExecutionResult();
      });
      final s = await ErdCatalog.loadNeighbourhood(
        delegate,
        SqlDialect.postgres,
        table: 'sales.orders',
      );
      expect(s.tables.map((t) => t.name).toSet(), {'sales.orders', 'customers'});
      expect(s.relations, hasLength(1));
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
      expect(moved.size.width, greaterThan(2000 + moved.widthFor('users')));
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
      // user_id is NOT NULL here: one or many.
      expect(m, contains('users ||--|{ orders : "user_id"'));
    });

    test('mermaid marks a nullable foreign key as zero or many', () {
      final s = ErdSchema.fromCatalog(columnRows: [
        ['users', 'id', 'int', '1', '0'],
        ['orders', 'user_id', 'int', '0', '1'],
      ], fkRows: [
        ['orders', 'user_id', 'users', 'id'],
      ]);
      expect(ErdExport.toMermaid(s), contains('users ||--o{ orders'));
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

    test('distance to a route is measured to its nearest segment', () {
      final pts = [
        const material.Offset(0, 0),
        const material.Offset(100, 0),
        const material.Offset(100, 50),
      ];
      expect(ErdGeometry.distanceToRoute(pts, const material.Offset(50, 4)),
          closeTo(4, 1e-9));
      expect(ErdGeometry.distanceToRoute(pts, const material.Offset(104, 25)),
          closeTo(4, 1e-9));
      expect(ErdGeometry.distanceToRoute(pts, const material.Offset(-3, 0)),
          closeTo(3, 1e-9));
    });

    test('svg marks an optional FK end with a circle, a mandatory one with a bar',
        () {
      String svgFor(String nullable) {
        final s = ErdSchema.fromCatalog(columnRows: [
          ['users', 'id', 'int', '1', '0'],
          ['orders', 'id', 'int', '1', '0'],
          ['orders', 'customer_id', 'int', '0', nullable],
        ], fkRows: [
          ['orders', 'customer_id', 'users', 'id'],
        ]);
        return ErdExport.toSvg(s, ErdLayout.compute(s));
      }

      expect(svgFor('1'), contains('<circle'));
      expect(svgFor('0'), isNot(contains('<circle')));
    });

    test('fit goes below the usual minimum zoom for a large diagram', () {
      final big = ErdLayout.fitScale(
          const material.Size(20000, 9000), const material.Size(1200, 700));
      expect(big, lessThan(0.2));
      expect(big, greaterThan(0));
      expect(20000 * big, lessThanOrEqualTo(1200));
      expect(ErdLayout.fitScale(
          const material.Size(400, 300), const material.Size(1200, 700)), 1);
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

    test('no SVG text is wider than its card, long names are cut (#1153)', () {
      const longTable = 'a_table_with_a_very_long_name_for_the_card';
      const longColumn = 'an_extremely_long_column_name_that_wont_fit';
      final s = ErdSchema.fromCatalog(columnRows: [
        [longTable, 'id', 'INTEGER', '1'],
        [longTable, longColumn, 'timestamp with time zone', '0'],
      ], fkRows: const []);
      final svg = ErdExport.toSvg(s, ErdLayout.compute(s));

      expect(svg, contains('…'));
      expect(svg, isNot(contains(longColumn)));
      final texts = RegExp(r'<text[^>]*>([^<]*)</text>')
          .allMatches(svg)
          .map((m) => m.group(1)!);
      expect(texts, isNotEmpty);
      for (final text in texts) {
        // The same per-glyph estimate the export cuts with: 7.5 px a glyph,
        // inside the widest card there is.
        expect(text.length * 7.5,
            lessThanOrEqualTo(ErdLayout.maxCardWidth - 20),
            reason: text);
      }
    });

    test('svg draws an edge and its end markers for every relation', () {
      final s = ErdSchema.fromCatalog(columnRows: [
        ['users', 'id', 'int', '1'],
        ['orders', 'id', 'int', '1'],
        ['orders', 'user_id', 'int', '0'],
        ['payments', 'id', 'int', '1'],
        ['payments', 'order_id', 'int', '0'],
        ['payments', 'user_id', 'int', '0'],
      ], fkRows: [
        ['orders', 'user_id', 'users', 'id'],
        ['payments', 'order_id', 'orders', 'id'],
        ['payments', 'user_id', 'users', 'id'],
      ]);
      final layout = ErdLayout.compute(s);
      final routes = ErdRouter.route(s, layout);
      final drawn = routes.where((r) => r.points.length >= 2).length;
      expect(drawn, s.relations.length);
      final svg = ErdExport.toSvg(s, layout, routes: routes);
      expect('class="erd-edge"'.allMatches(svg).length, drawn);
      expect('class="erd-ends"'.allMatches(svg).length, drawn);
      expect('<title>'.allMatches(svg).length, drawn);
    });

    test('svg shortens long table and column names to fit the card', () {
      const table = 'customer_order_line_items_with_a_very_long_name';
      const column = 'shipping_address_second_line_for_international_orders';
      final s = ErdSchema.fromCatalog(columnRows: [
        [table, column, 'text', '0'],
      ], fkRows: const []);
      final svg = ErdExport.toSvg(s, ErdLayout.compute(s));
      expect(svg, isNot(contains(table)));
      expect(svg, isNot(contains(column)));
      expect('…'.allMatches(svg).length, greaterThanOrEqualTo(2));
    });

    test('svg lines up the column names of a card past the key slot', () {
      final svg = ErdExport.toSvg(sample(), ErdLayout.compute(sample()));
      double xOf(String name) => double.parse(
          RegExp('<text x="([0-9.]+)" y="[0-9.]+"[^>]*>$name</text>')
              .firstMatch(svg)!
              .group(1)!);
      // users: "id" is a PK, "name" is not; both start at the same x.
      expect(xOf('name'), xOf('id'));
    });

    test('svg takes its colours from the caller', () {
      final s = sample();
      final svg = ErdExport.toSvg(s, ErdLayout.compute(s),
          colors: const ErdSvgColors(background: '#123456', edge: '#abcdef'));
      expect(svg, contains('fill="#123456"'));
      expect(svg, contains('stroke="#abcdef"'));
      expect(svg, contains('rx="8.0"'));
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
          source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite),
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

      await t.tap(find.byKey(const material.ValueKey('erd_export')));
      await t.pump();
      await t.tap(find.text('Mermaid (.mmd)'));
      await t.pump();
      expect(utf8.decode(saved['erd.mmd']!), contains('erDiagram'));

      await t.tap(find.byKey(const material.ValueKey('erd_export')));
      await t.pump();
      await t.tap(find.text('SVG'));
      // The export reads its setting first, which is real I/O.
      for (var i = 0; i < 40 && !saved.containsKey('erd.svg'); i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      expect(utf8.decode(saved['erd.svg']!), contains('<svg'));
      // The dark test theme still exports the light palette by default.
      expect(utf8.decode(saved['erd.svg']!),
          contains('<rect width="100%" height="100%" fill="#ffffff"/>'));

      final card = find.byKey(const material.ValueKey('erd_table_users'));
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(card);
      await t.pump();
      expect(opened, 'users');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('PNG export works while a table is picked', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      final saved = <String, Uint8List>{};
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite),
          onSaveFile: (n, b) async => saved[n] = b,
        ),
      ));
      await t.pump();
      await t.pump();

      // A single tap picks the table once the double-tap window has passed.
      await t.tap(find.byKey(const material.ValueKey('erd_table_users')));
      await t.pump(const Duration(milliseconds: 400));

      await t.tap(find.byKey(const material.ValueKey('erd_export')));
      await t.pumpAndSettle();
      await t.tap(find.text('PNG'));
      // The capture waits for a frame without the pick, then for the engine.
      for (var i = 0; i < 40 && !saved.containsKey('erd.png'); i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      expect(saved['erd.png'], isNotNull);
      expect(saved['erd.png']!.isNotEmpty, isTrue);
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 1));
    });

    // The card menu is a desktop popover; on a phone platform shadcn opens it
    // as a sheet, which needs the app's drawer overlay.
    final desktop = TargetPlatformVariant.only(material.TargetPlatform.linux);

    testWidgets('a card menu opens the table in SQL and shows its relations',
        variant: desktop, (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      String? inSql, relations;
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite),
          onOpenTable: (_) {},
          onOpenInSql: (n) => inSql = n,
          onShowRelations: (n) => relations = n,
        ),
      ));
      await t.pump();
      await t.pump();
      final card = find.byKey(const material.ValueKey('erd_table_users'));

      await t.tap(card, buttons: kSecondaryButton);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Open data'), findsOneWidget);
      await t.tap(find.byKey(const material.ValueKey('erd_menu_sql_users')));
      await t.pump(const Duration(milliseconds: 300));
      expect(inSql, 'users');

      await t.tap(card, buttons: kSecondaryButton);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(
          find.byKey(const material.ValueKey('erd_menu_relations_users')));
      await t.pump(const Duration(milliseconds: 300));
      expect(relations, 'users');
    });

    testWidgets('a card menu leaves out actions nobody handles',
        variant: desktop, (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(const material.ValueKey('erd_table_users')),
          buttons: kSecondaryButton);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Copy name'), findsOneWidget);
      expect(find.text('Open in SQL'), findsNothing);
      expect(find.text('Show relations'), findsNothing);
    });

    testWidgets('hovering an edge names its columns at any zoom', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();

      // The same schema, layout and routes as the view draws.
      final schema = ErdSchema.fromCatalog(columnRows: [
        ['users', 'id', 'INTEGER', '1'],
        ['orders', 'user_id', 'INTEGER', '0'],
      ], fkRows: [
        ['orders', 'user_id', 'users', 'id'],
      ]);
      final layout = ErdLayout.compute(schema);
      final route = ErdRouter.route(schema, layout).single.points;
      // Middle of the longest segment: on the edge, away from the cards.
      var a = route[0], b = route[1];
      for (var i = 1; i < route.length; i++) {
        if ((route[i] - route[i - 1]).distance > (b - a).distance) {
          a = route[i - 1];
          b = route[i];
        }
      }
      final onEdge = (a + b) / 2;

      material.Offset toScreen(material.Offset canvas, double scale) {
        final card = t.getTopLeft(
            find.byKey(const material.ValueKey('erd_table_users')));
        return card + (canvas - layout.positions['users']!) * scale;
      }

      double scale() => int.parse(t
              .widget<material.Text>(
                  find.byKey(const material.ValueKey('erd_zoom_label')))
              .data!
              .replaceAll('%', '')) /
          100;

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: material.Offset.zero);
      await mouse.moveTo(toScreen(onEdge, scale()));
      await t.pump();
      const label = 'orders.user_id → users.id';
      expect(find.text(label), findsOneWidget);
      final height = t.getSize(find.byKey(const material.ValueKey('erd_edge_tip'))).height;

      // Zoomed out, the label keeps its screen size.
      await mouse.moveTo(material.Offset.zero);
      await t.pump();
      await t.tap(find.byKey(const material.ValueKey('erd_zoom_out')));
      await t.pump();
      await mouse.moveTo(toScreen(onEdge, scale()));
      await t.pump();
      expect(find.text(label), findsOneWidget);
      expect(
          t.getSize(find.byKey(const material.ValueKey('erd_edge_tip'))).height,
          closeTo(height, 0.5));
    });

    testWidgets('hovering a card rebuilds only the cards it changes',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      final wide = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return SqlExecutionResult(rows: [
            for (var i = 0; i < 20; i++) ['t$i', 'id', 'INTEGER', '1'],
            ['child', 'id', 'INTEGER', '1'],
            ['child', 't0_id', 'INTEGER', '0'],
          ]);
        }
        return const SqlExecutionResult(rows: [
          ['child', 't0_id', 't0', 'id'],
        ]);
      });
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: wide, dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();
      await t.pump();

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: material.Offset.zero);

      // The first hover changes one card's focus: only that card rebuilds.
      erdCardBuilds = 0;
      await mouse.moveTo(
          t.getCenter(find.byKey(const material.ValueKey('erd_table_t5'))));
      await t.pump();
      expect(erdCardBuilds, 1);

      // Moving to child: t5 loses the highlight, child and t0 gain it. The
      // other twenty cards stay as they are.
      erdCardBuilds = 0;
      await mouse.moveTo(
          t.getCenter(find.byKey(const material.ValueKey('erd_table_child'))));
      await t.pump();
      expect(erdCardBuilds, greaterThan(0));
      expect(erdCardBuilds, lessThanOrEqualTo(3));
    });

    testWidgets('Copy Mermaid puts the diagram on the clipboard', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();

      await t.tap(find.byKey(const material.ValueKey('erd_export')));
      await t.pump();
      await t.tap(find.text('Copy Mermaid'));
      await t.pump();
      expect(copied, startsWith('erDiagram'));
      expect(copied, contains('users ||--|{ orders'));
      // The toast's 5 s timer starts after its entry animation: step the
      // clock frame by frame until it has gone.
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('hiding every table says so and offers them back',
        variant: desktop, (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();

      for (final table in ['users', 'orders']) {
        await t.tap(find.byKey(material.ValueKey('erd_table_$table')),
            buttons: kSecondaryButton);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text('Hide from diagram'));
        // Let the menu popover close, or it takes the next tap.
        await t.pumpAndSettle();
      }
      expect(find.text('All tables are hidden'), findsOneWidget);
      expect(find.text('No tables found'), findsNothing);

      await t.tap(find.text('Show all tables'));
      await t.pump();
      await t.pump();
      expect(find.byKey(const material.ValueKey('erd_table_users')),
          findsOneWidget);
    });

    testWidgets('an empty schema names the database', (t) async {
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(
              delegate: FakeSqlExecutionDelegate(
                  onExecute: (_) => const SqlExecutionResult()),
              dialect: SqlDialect.postgres),
          databaseName: 'shop',
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('No tables found'), findsOneWidget);
      expect(find.textContaining('shop'), findsOneWidget);
    });

    testWidgets('a card can be dragged and Auto layout puts it back',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
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
        child: ErdView(source: SqlErdSource(delegate: junction, dialect: SqlDialect.sqlite)),
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
        child: ErdView(source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
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
        child: ErdView(source: SqlErdSource(delegate: threeTables(), dialect: SqlDialect.sqlite)),
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
        child: ErdView(source: SqlErdSource(delegate: threeTables(), dialect: SqlDialect.sqlite)),
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

    String zoomLabel(WidgetTester t) => t
        .widget<material.Text>(
            find.byKey(const material.ValueKey('erd_zoom_label')))
        .data!;

    testWidgets('a large diagram fits the viewport on first load', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      final tall = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return SqlExecutionResult(rows: [
            for (final table in ['a', 'b', 'c'])
              for (var i = 0; i < 400; i++) [table, 'col$i', 'INTEGER', '0'],
          ]);
        }
        return const SqlExecutionResult();
      });
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: tall, dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();
      await t.pump();
      final percent = int.parse(zoomLabel(t).replaceAll('%', ''));
      // A card of 400 rows is about 8 800 px tall: below the usual 20 % floor.
      expect(percent, lessThan(20));
      expect(percent, greaterThan(0));
    });

    testWidgets('Ctrl+Shift+= ("+") zooms in', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: delegate(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();
      expect(zoomLabel(t), '100%');

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.equal);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(zoomLabel(t), '125%');
    });

    testWidgets('a search that matches nothing says so (#1157)', (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(source: SqlErdSource(delegate: threeTables(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyF);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      await t.pump();

      await t.enterText(find.byType(material.EditableText), 'zzz');
      await t.pump();
      expect(find.text('No tables match'), findsOneWidget);
    });

    testWidgets('double click opens a table of another schema by its name (#1155)',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      String? opened;
      final sales = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(rows: [
            ['sales.orders', 'id', 'INTEGER', '1'],
          ]);
        }
        return const SqlExecutionResult();
      });
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(delegate: sales, dialect: SqlDialect.sqlite),
          onOpenTable: (n) => opened = n,
        ),
      ));
      await t.pump();
      await t.pump();

      final card = find.byKey(const material.ValueKey('erd_table_sales.orders'));
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 400));
      expect(opened, 'sales.orders');
    });

    testWidgets('Enter in the search picks the table and closes the search',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: threeTables(), dialect: SqlDialect.sqlite)),
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
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.pump();

      expect(find.byType(material.EditableText), findsNothing);
      expect(opacityOf(t, 'lonely'), contains(0.35));

      // The canvas has the keyboard again: Esc clears the pick.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(opacityOf(t, 'lonely'), isNot(contains(0.35)));
    });

    testWidgets('Esc closes an open search and keeps the picked table',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
            source: SqlErdSource(delegate: threeTables(), dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();

      await t.tap(find.byKey(const material.ValueKey('erd_table_orders')));
      await t.pump(const Duration(milliseconds: 400));
      expect(opacityOf(t, 'lonely'), contains(0.35));

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyF);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      await t.pump();
      expect(find.byType(material.EditableText), findsOneWidget);

      // The empty field drops the focus on Esc; the search closes.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump();
      expect(find.byType(material.EditableText), findsNothing);
      expect(opacityOf(t, 'lonely'), contains(0.35));

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(opacityOf(t, 'lonely'), isNot(contains(0.35)));
    });

    testWidgets('keys only hides plain columns and the toggle brings them back',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      final wide = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(rows: [
            ['users', 'id', 'INTEGER', '1'],
            ['orders', 'id', 'INTEGER', '1'],
            ['orders', 'user_id', 'INTEGER', '0'],
            ['orders', 'amount', 'REAL', '0'],
          ]);
        }
        return const SqlExecutionResult(rows: [
          ['orders', 'user_id', 'users', 'id'],
        ]);
      });
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(source: SqlErdSource(delegate: wide, dialect: SqlDialect.sqlite)),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('amount'), findsOneWidget);

      await t.tap(find.byKey(const material.ValueKey('erd_keys_only')));
      await t.pump();
      expect(find.text('amount'), findsNothing);
      expect(find.text('user_id'), findsOneWidget);

      await t.tap(find.byKey(const material.ValueKey('erd_keys_only')));
      await t.pump();
      expect(find.text('amount'), findsOneWidget);
    });

    testWidgets('a failed load shows a titled state with Retry', (t) async {
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(delegate: FakeSqlExecutionDelegate(
              onExecute: (sql) => throw StateError('no access')), dialect: SqlDialect.sqlite),
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('Could not load the schema'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows empty state', (t) async {
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(delegate: FakeSqlExecutionDelegate(
              onExecute: (_) => const SqlExecutionResult()), dialect: SqlDialect.postgres),
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.text('No tables found'), findsOneWidget);
    });
  });

  group('catalog limit (#1218)', () {
    test('a catalog read asks for the explicit row limit', () async {
      final limits = <int?>[];
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        return const SqlExecutionResult();
      });
      final recording = _LimitRecordingDelegate(delegate, limits);
      await ErdCatalog.load(recording, SqlDialect.sqlite);
      expect(limits, [ErdCatalog.catalogRowLimit, ErdCatalog.catalogRowLimit]);
    });

    test('a cut catalog is reported as truncated', () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
        if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
          return const SqlExecutionResult(
            rows: [
              ['users', 'id', 'INTEGER', '1'],
            ],
            isTruncated: true,
          );
        }
        return const SqlExecutionResult();
      });
      final schema = await ErdCatalog.load(delegate, SqlDialect.sqlite);
      expect(schema.truncated, isTrue);
      expect(schema.tables.map((t) => t.name), ['users']);
    });

    test('a complete catalog is not truncated', () async {
      final delegate = FakeSqlExecutionDelegate(onExecute: (_) {
        return const SqlExecutionResult(rows: [
          ['users', 'id', 'INTEGER', '1'],
        ]);
      });
      final schema = await ErdCatalog.load(delegate, SqlDialect.sqlite);
      expect(schema.truncated, isFalse);
    });
  });

  group('router on a larger schema (#1168)', () {
    test('a 100-table schema routes every relation with a real path', () {
      final columns = <List<String>>[];
      final fks = <List<String>>[];
      for (var i = 0; i < 100; i++) {
        columns.add(['t$i', 'id', 'int', '1', '0']);
        columns.add(['t$i', 'parent_id', 'int', '0', '1']);
        if (i > 0) {
          fks.add(['t$i', 'parent_id', 't${i ~/ 2}', 'id']);
        }
        if (i > 10 && i % 7 == 0) {
          fks.add(['t$i', 'parent_id', 't${i - 9}', 'id']);
        }
      }
      final schema = ErdSchema.fromCatalog(columnRows: columns, fkRows: fks);
      final layout = ErdLayout.compute(schema);
      final routes = ErdRouter.route(schema, layout);

      expect(routes.length, schema.relations.length);
      for (final r in routes) {
        expect(r.points.length, greaterThanOrEqualTo(2));
      }
    });
  });
}

/// Passes every call on and records the row limit it was given.
class _LimitRecordingDelegate extends SqlExecutionDelegate {
  _LimitRecordingDelegate(this._inner, this._limits);

  final SqlExecutionDelegate _inner;
  final List<int?> _limits;

  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  }) {
    _limits.add(limit);
    return _inner.executeQuery(sql, limit: limit, timeout: timeout);
  }

  @override
  Future<String> explainQuery(String sql) => _inner.explainQuery(sql);

  @override
  bool get supportsExplain => false;

  @override
  Future<void> cancelQuery() async {}

  @override
  bool get supportsTransactions => false;
}
