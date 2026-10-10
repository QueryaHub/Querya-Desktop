import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// #1276: cards sized to their content, header colours.
ErdTable _table(String name, List<(String, String)> columns) => ErdTable(
      name: name,
      columns: [
        for (final (n, t) in columns) ErdColumn(name: n, type: t),
      ],
    );

void main() {
  group('card width', () {
    test('a short table is narrower than a wide one, both within bounds', () {
      final short = _table('tags', [('id', 'int')]);
      final wide = _table('events', [
        ('created_at', 'timestamp with time zone'),
        ('payload', 'jsonb'),
      ]);
      expect(ErdLayout.widthOf(short), ErdLayout.minCardWidth);
      expect(ErdLayout.widthOf(wide), greaterThan(ErdLayout.cardWidth));
      expect(ErdLayout.widthOf(wide), lessThanOrEqualTo(ErdLayout.maxCardWidth));
    });

    test('a very long column is capped at the maximum', () {
      final huge = _table('t', [('a' * 80, 'character varying(255)')]);
      expect(ErdLayout.widthOf(huge), ErdLayout.maxCardWidth);
    });

    test('cards of different widths in one layer do not overlap the next', () {
      final s = ErdSchema.fromCatalog(columnRows: [
        ['users', 'id', 'int', '1'],
        ['users', 'created_at', 'timestamp with time zone', '0'],
        ['orders', 'id', 'int', '1'],
        ['orders', 'user_id', 'int', '0'],
      ], fkRows: [
        ['orders', 'user_id', 'users', 'id'],
      ]);
      final l = ErdLayout.compute(s);
      final rects = [for (final t in s.tables) l.rectOf(t)];
      expect(rects[0].overlaps(rects[1]), isFalse);
      expect(l.rectOf(s.tables.first).width, ErdLayout.widthOf(s.tables.first));
    });

    testWidgets('a type is shown whole: the card is measured, not estimated',
        (t) async {
      await t.binding.setSurfaceSize(const material.Size(1200, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(queryaThemeTestShell(
        child: ErdView(
          source: SqlErdSource(
            delegate: FakeSqlExecutionDelegate(onExecute: (sql) {
              if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
                return const SqlExecutionResult(rows: [
                  ['events', 'id', 'INTEGER', '1'],
                  ['events', 'created', 'timestamp(6)', '0'],
                ]);
              }
              return const SqlExecutionResult();
            }),
            dialect: SqlDialect.sqlite,
          ),
        ),
      ));
      await t.pump();
      await t.pump();
      // Measured in the test font, whatever its glyph widths.
      final type = find.text('timestamp(6)');
      expect(type, findsOneWidget);
      expect(t.renderObject<RenderParagraph>(type).didExceedMaxLines, isFalse);
      expect(t.getSize(find.byKey(const material.ValueKey('erd_table_events'))).width,
          greaterThan(ErdLayout.cardWidth));
    });
  });

  group('header colour', () {
    test('tables of one schema share a slot, the current schema has none', () {
      final a = erdHeaderSlot('sales.orders', const {});
      expect(a, isNotNull);
      expect(erdHeaderSlot('sales.items', const {}), a);
      expect(erdHeaderSlot('orders', const {}), isNull);
    });

    test('a picked slot wins over the schema one', () {
      expect(erdHeaderSlot('orders', const {'orders': 'type4'}), 'type4');
      expect(erdHeaderSlot('sales.orders', const {'sales.orders': 'type2'}),
          'type2');
    });

    test('picked colours are kept with the layout, unknown slots dropped', () {
      const layout = ErdSavedLayout(headerColors: {'orders': 'type3'});
      final back = ErdSavedLayout.decode(layout.encode())!;
      expect(back.headerColors, {'orders': 'type3'});
      expect(
          ErdSavedLayout.decode('{"headerColors":{"a":"#ff0000"}}')!
              .headerColors,
          isEmpty);
      expect(layout.keepOnly({'users'}).headerColors, isEmpty);
    });

    test('the SVG uses a per-table header fill when given one', () {
      final s = ErdSchema.fromCatalog(
          columnRows: const [
            ['orders', 'id', 'int', '1'],
            ['users', 'id', 'int', '1'],
          ],
          fkRows: const []);
      final svg = ErdExport.toSvg(s, ErdLayout.compute(s),
          headerFills: const {'orders': '#abcdef'});
      expect('fill="#abcdef"'.allMatches(svg), hasLength(1));
      expect(svg, contains('fill="${const ErdSvgColors().header}"'));
    });
  });

  testWidgets('a row shows UQ, AI and DF and lists them in its tooltip (#1277)',
      (t) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(
      child: ErdView(
        source: SqlErdSource(
          delegate: FakeSqlExecutionDelegate(onExecute: (sql) {
            if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
              return const SqlExecutionResult(rows: [
                ['users', 'id', 'INTEGER', '1', '0', '0', 'NULL', '1'],
                ['users', 'email', 'TEXT', '0', '0', '1', 'NULL', '0'],
                ['users', 'status', 'TEXT', '0', '1', '0', "'new'", '0'],
              ]);
            }
            return const SqlExecutionResult();
          }),
          dialect: SqlDialect.sqlite,
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.byKey(const material.ValueKey('erd_badge_users_id_AI')),
        findsOneWidget);
    expect(find.byKey(const material.ValueKey('erd_badge_users_email_UQ')),
        findsOneWidget);
    expect(find.byKey(const material.ValueKey('erd_badge_users_status_DF')),
        findsOneWidget);
    expect(find.byKey(const material.ValueKey('erd_badge_users_id_UQ')),
        findsNothing);
    final tip = t.widget<material.Tooltip>(find.ancestor(
      of: find.byKey(const material.ValueKey('erd_badge_users_status_DF')),
      matching: find.byType(material.Tooltip),
    ));
    expect(tip.message, contains("Default: 'new'"));
    expect(tip.message, contains('Nullable'));
  });
}
