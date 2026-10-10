import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';

/// #1282: table groups.
ErdSchema _schema() => ErdSchema.fromCatalog(columnRows: const [
      ['users', 'id', 'int', '1'],
      ['orders', 'id', 'int', '1'],
      ['orders', 'user_id', 'int', '0'],
      ['items', 'order_id', 'int', '0'],
      ['tags', 'id', 'int', '1'],
      ['logs', 'id', 'int', '1'],
      ['audit', 'id', 'int', '1'],
    ], fkRows: const [
      ['orders', 'user_id', 'users', 'id'],
      ['items', 'order_id', 'orders', 'id'],
    ]);

void main() {
  group('saved groups', () {
    const g = ErdGroup(
      id: 'g1',
      name: 'Billing',
      color: 'type3',
      note: 'Money in and out',
      tables: ['orders', 'items'],
    );

    test('come back from JSON with their name, colour, note and tables', () {
      final back =
          ErdSavedLayout.decode(const ErdSavedLayout(groups: [g]).encode())!;
      final r = back.groups.single;
      expect((r.id, r.name, r.color, r.note), ('g1', 'Billing', 'type3',
          'Money in and out'));
      expect(r.tables, ['orders', 'items']);
      expect(const ErdSavedLayout(groups: [g]).isEmpty, isFalse);
    });

    test('broken entries are dropped, a table stays in its first group', () {
      final back = ErdSavedLayout.decode('{"groups": ['
          '{"id": "g1", "name": "A", "color": "type1", "tables": ["users"]},'
          '{"id": "g2", "name": "B", "color": "type2", '
          '"tables": ["users", "tags"]},'
          '{"id": "g3", "name": "", "color": "type1", "tables": ["logs"]},'
          '{"id": "g4", "name": "C", "color": "#ff0000", "tables": ["logs"]},'
          '{"id": "schema:sales", "name": "D", "color": "type1", '
          '"tables": ["audit"]},'
          '{"id": "g5", "name": "E", "color": "type1", "tables": []}'
          ']}')!;
      expect([for (final g in back.groups) '${g.id}: ${g.tables.join(', ')}'],
          ['g1: users', 'g2: tags']);
    });

    test('keepOnly drops gone tables and the groups left empty', () {
      const layout = ErdSavedLayout(groups: [
        g,
        ErdGroup(id: 'g2', name: 'Old', color: 'type1', tables: ['gone']),
      ]);
      final kept = layout.keepOnly({'orders', 'users'});
      expect(kept.groups.single.tables, ['orders']);
    });
  });

  group('schema groups', () {
    test('only when the diagram spans several schemas', () {
      expect(erdSchemaGroups(['users', 'orders'], const []), isEmpty);
      expect(erdSchemaGroups(['sales.a', 'sales.b'], const []), isEmpty);
    });

    test('one per named schema, without the tables a user group holds', () {
      final groups = erdSchemaGroups(
        ['users', 'sales.orders', 'sales.items', 'hr.staff'],
        const [
          ErdGroup(id: 'g1', name: 'Mine', color: 'type1', tables: ['hr.staff']),
        ],
      );
      expect(groups, hasLength(1));
      expect(groups.single.name, 'sales');
      expect(groups.single.tables, ['sales.orders', 'sales.items']);
      expect(groups.single.isSchema, isTrue);
      expect(groups.single.color, erdHeaderSlot('sales.orders', const {}));
    });
  });

  group('layout', () {
    test('a group is laid out as a block clear of the other cards', () {
      final s = _schema();
      final group = ['users', 'tags'];
      final l = ErdLayout.compute(s, groups: [group]);
      final frame = l.frameOf(group)!;
      for (final t in s.tables) {
        final rect = l.rectOf(t);
        if (group.contains(t.name)) {
          expect(frame.contains(rect.topLeft) && frame.contains(rect.bottomRight),
              isTrue, reason: t.name);
        } else {
          expect(frame.overlaps(rect), isFalse, reason: t.name);
        }
      }
      // Every card is placed, none overlaps another.
      final rects = [for (final t in s.tables) l.rectOf(t)];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
      // The frame's title band fits on the canvas.
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.left, greaterThanOrEqualTo(0));
    });

    test('two groups do not overlap, unknown tables are ignored', () {
      final s = _schema();
      final l = ErdLayout.compute(s, groups: [
        ['users', 'orders', 'items'],
        ['tags', 'logs', 'nope'],
      ]);
      expect(
          l.frameOf(['users', 'orders', 'items'])!
              .overlaps(l.frameOf(['tags', 'logs'])!),
          isFalse);
      expect(l.positions.keys.toSet(), {for (final t in s.tables) t.name});
    });

    test('a frame wraps its cards with padding and a title band', () {
      final s = _schema();
      final l = ErdLayout.compute(s);
      final users = l.rectOf(s.tables.firstWhere((t) => t.name == 'users'));
      final frame = l.frameOf(['users', 'missing'])!;
      expect(frame.left, users.left - ErdLayout.framePadding);
      expect(frame.top,
          users.top - ErdLayout.framePadding - ErdLayout.frameTitleHeight);
      expect(frame.bottom, users.bottom + ErdLayout.framePadding);
      expect(l.frameOf(['missing']), isNull);
    });

    test('withPositions moves several cards at once', () {
      final s = _schema();
      final l = ErdLayout.compute(s).withPositions({
        'users': const Offset(500, 400),
        'tags': const Offset(-20, 600),
      });
      expect(l.positions['users'], const Offset(500, 400));
      expect(l.positions['tags'], const Offset(8, 600));
    });
  });

  test('the SVG draws a frame and a title per group', () {
    final s = _schema();
    final l = ErdLayout.compute(s, groups: [
      ['users', 'orders'],
    ]);
    final svg = ErdExport.toSvg(s, l, groups: [
      ErdSvgGroup(
        name: 'Billing & co',
        frame: l.frameOf(['users', 'orders'])!,
        fill: '#f0f0ff',
        stroke: '#3366ff',
      ),
    ]);
    expect('class="erd-group"'.allMatches(svg).length, 1);
    expect(svg, contains('>Billing &amp; co</text>'));
    // Under the edges.
    expect(svg.indexOf('erd-group'), lessThan(svg.indexOf('erd-edge')));
  });
}
