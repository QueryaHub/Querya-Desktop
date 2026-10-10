import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_group_ops.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

ErdGroup _group(String id, List<String> tables, {String? name}) => ErdGroup(
      id: id,
      name: name ?? 'Group $id',
      color: erdHeaderSlots.first,
      tables: tables,
    );

void main() {
  group('ErdGroupOps.groupOf', () {
    test('finds the group of a table', () {
      final groups = [_group('g1', ['a', 'b']), _group('g2', ['c'])];
      expect(ErdGroupOps.groupOf(groups, 'c')?.id, 'g2');
      expect(ErdGroupOps.groupOf(groups, 'z'), isNull);
    });
  });

  group('ErdGroupOps.ungroupTables', () {
    test('removes tables and drops a group left empty', () {
      final groups = [_group('g1', ['a', 'b']), _group('g2', ['c'])];
      final out = ErdGroupOps.ungroupTables(groups, {'a', 'c'});
      expect(out.map((g) => g.id), ['g1']);
      expect(out.single.tables, ['b']);
    });

    test('keeps the group named in except', () {
      final groups = [_group('g1', ['a']), _group('g2', ['a', 'b'])];
      final out = ErdGroupOps.ungroupTables(groups, {'a'}, except: 'g2');
      expect(out.map((g) => g.id), ['g2']);
      expect(out.single.tables, ['a', 'b']);
    });

    test('does not change its argument', () {
      final groups = [_group('g1', ['a'])];
      ErdGroupOps.ungroupTables(groups, {'a'});
      expect(groups.single.tables, ['a']);
    });
  });

  group('ErdGroupOps numbering', () {
    test('nextNameNumber skips taken default names', () {
      final groups = [_group('g1', ['a'], name: 'Group 2')];
      expect(ErdGroupOps.nextNameNumber(groups), 3);
    });

    test('nextIdNumber skips taken ids', () {
      final groups = [_group('g1', ['a']), _group('g2', ['b'])];
      expect(ErdGroupOps.nextIdNumber(groups), 3);
      expect(ErdGroupOps.nextIdNumber(const []), 1);
    });
  });

  group('ErdGroupOps.withNewGroup', () {
    test('moves tables into a new group in diagram order', () {
      final groups = [_group('g1', ['a', 'b'])];
      final out = ErdGroupOps.withNewGroup(
        groups,
        tables: {'c', 'a'},
        tableNames: ['a', 'b', 'c'],
        name: 'Billing',
        note: 'money',
      );
      expect(out.map((g) => g.id), ['g1', 'g2']);
      expect(out.first.tables, ['b']);
      expect(out.last.name, 'Billing');
      expect(out.last.note, 'money');
      expect(out.last.tables, ['a', 'c']);
      expect(out.last.color, erdHeaderSlots[1 % erdHeaderSlots.length]);
    });
  });

  group('ErdGroupOps.addTables', () {
    test('takes tables from other groups and appends new ones', () {
      final groups = [_group('g1', ['a', 'b']), _group('g2', ['c'])];
      final out = ErdGroupOps.addTables(groups, 'g2', {'a', 'c', 'd'});
      expect(out.firstWhere((g) => g.id == 'g1').tables, ['b']);
      expect(out.firstWhere((g) => g.id == 'g2').tables, ['c', 'a', 'd']);
    });

    test('only ungroups when the group is unknown', () {
      final groups = [_group('g1', ['a', 'b'])];
      final out = ErdGroupOps.addTables(groups, 'missing', {'a'});
      expect(out.single.tables, ['b']);
    });
  });
}
