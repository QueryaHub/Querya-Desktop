import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/core/erd/erd_geometry.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// #1281: one-to-one ends, `1` / `*` labels, picking a relation, link tables.
material.Widget _view(List<List<String>> columns, List<List<String>> fks) =>
    queryaThemeTestShell(
      child: ErdView(
        source: SqlErdSource(
          delegate: FakeSqlExecutionDelegate(onExecute: (sql) {
            if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
              return SqlExecutionResult(rows: columns);
            }
            return SqlExecutionResult(rows: fks);
          }),
          dialect: SqlDialect.sqlite,
        ),
      ),
    );

void main() {
  group('svg', () {
    test('a one-to-one end draws a bar, both ends are labelled', () {
      final many = ErdSchema.fromCatalog(columnRows: const [
        ['users', 'id', 'int', '1'],
        ['orders', 'user_id', 'int', '0'],
      ], fkRows: const [
        ['orders', 'user_id', 'users', 'id'],
      ]);
      final one = ErdSchema.fromCatalog(columnRows: const [
        ['users', 'id', 'int', '1'],
        ['profiles', 'user_id', 'int', '0', '0', '1'],
      ], fkRows: const [
        ['profiles', 'user_id', 'users', 'id'],
      ]);
      expect(one.relations.single.oneToOne, isTrue);

      List<String> labels(String svg) => [
            for (final m in RegExp(r'class="erd-end-label"[^>]*>([^<]*)<')
                .allMatches(svg))
              m.group(1)!,
          ];
      String ends(String svg) =>
          RegExp(r'class="erd-ends" d="([^"]*)"').firstMatch(svg)!.group(1)!;

      final manySvg = ErdExport.toSvg(many, ErdLayout.compute(many));
      final oneSvg = ErdExport.toSvg(one, ErdLayout.compute(one));
      expect(labels(manySvg), ['*', '1']);
      expect(labels(oneSvg), ['1', '1']);
      // A crow's foot is three strokes, a bar one: the one-to-one end draws
      // two fewer.
      final strokes = RegExp('M ');
      expect(strokes.allMatches(ends(oneSvg)).length,
          strokes.allMatches(ends(manySvg)).length - 2);
    });

    test('an end label sits beside the edge, clear of the card', () {
      const edge = material.Offset(100, 50);
      final label = ErdGeometry.endLabel(edge, const material.Offset(200, 50));
      expect(label.dx, greaterThan(edge.dx));
      expect(label.dy, isNot(edge.dy));
    });
  });

  testWidgets('a click on an edge picks it until Esc', (t) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    const columns = [
      ['users', 'id', 'INTEGER', '1'],
      ['orders', 'user_id', 'INTEGER', '0'],
    ];
    const fks = [
      ['orders', 'user_id', 'users', 'id'],
    ];
    await t.pumpWidget(_view(columns, fks));
    await t.pump();
    await t.pump();

    // The same schema, layout and routes as the view draws.
    final schema = ErdSchema.fromCatalog(columnRows: columns, fkRows: fks);
    final layout = ErdLayout.compute(schema);
    final route = ErdRouter.route(schema, layout).single.points;
    var a = route[0], b = route[1];
    for (var i = 1; i < route.length; i++) {
      if ((route[i] - route[i - 1]).distance > (b - a).distance) {
        a = route[i - 1];
        b = route[i];
      }
    }
    final scale = int.parse(t
            .widget<material.Text>(
                find.byKey(const material.ValueKey('erd_zoom_label')))
            .data!
            .replaceAll('%', '')) /
        100;
    final onEdge = t.getTopLeft(
            find.byKey(const material.ValueKey('erd_table_users'))) +
        ((a + b) / 2 - layout.positions['users']!) * scale;

    final usersId = find.byKey(
        const material.ValueKey('erd_focus_column_users_id'));
    final ordersUserId = find.byKey(
        const material.ValueKey('erd_focus_column_orders_user_id'));
    const label = 'orders.user_id → users.id';

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: material.Offset.zero);
    await mouse.moveTo(onEdge);
    await t.pump();
    expect(usersId, findsNothing);
    await mouse.down(onEdge);
    await mouse.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(usersId, findsOneWidget);
    expect(ordersUserId, findsOneWidget);

    // The label stays when the mouse leaves the edge.
    await mouse.moveTo(const material.Offset(5, 5));
    await t.pump();
    expect(find.text(label), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(usersId, findsNothing);
    expect(ordersUserId, findsNothing);
    expect(find.text(label), findsNothing);
  });

  testWidgets('a link table is marked many-to-many', (t) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_view(const [
      ['users', 'id', 'INTEGER', '1'],
      ['roles', 'id', 'INTEGER', '1'],
      ['user_roles', 'user_id', 'INTEGER', '1'],
      ['user_roles', 'role_id', 'INTEGER', '1'],
    ], const [
      ['user_roles', 'user_id', 'users', 'id'],
      ['user_roles', 'role_id', 'roles', 'id'],
    ]));
    await t.pump();
    await t.pump();
    expect(find.byKey(const material.ValueKey('erd_junction_user_roles')),
        findsOneWidget);
    expect(find.byKey(const material.ValueKey('erd_junction_users')),
        findsNothing);
    final chip = t.widget<material.Tooltip>(find.ancestor(
        of: find.byKey(const material.ValueKey('erd_junction_user_roles')),
        matching: find.byType(material.Tooltip)).first);
    expect(chip.message, contains('users and roles'));
  });
}
