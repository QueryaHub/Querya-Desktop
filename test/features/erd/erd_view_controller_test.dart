
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_view_controller.dart';

/// The diagram's user state and its rules, without a widget tree (#1690).
void main() {
  late ErdViewController c;
  setUp(() => c = ErdViewController());

  const names = ['users', 'orders', 'items', 'tags'];

  group('groups', () {
    test('a new group takes the tables out of other groups and clears marks',
        () {
      c.marked.addAll({'users', 'orders'});
      final first = c.createGroup(
          tables: {'users', 'orders'}, tableNames: names, name: 'Core');
      expect(c.groupOf('users')?.name, 'Core');
      expect(c.marked, isEmpty);

      final second = c.createGroup(
          tables: {'orders', 'items'}, tableNames: names, name: 'Sales');
      expect(second, isNot(first));
      expect(c.groupOf('orders')?.name, 'Sales');
      expect(c.groupOf('users')?.name, 'Core');
      expect(c.groups.last.id, second);
    });

    test('adding to a missing group changes nothing and keeps the marks', () {
      c.marked.add('tags');
      c.addToGroup('nope', {'tags'});
      expect(c.groups, isEmpty);
      expect(c.marked, {'tags'});
    });

    test('adding to a group clears the marks; update finds by id', () {
      final id = c.createGroup(
          tables: {'users'}, tableNames: names, name: 'A');
      c.marked.add('tags');
      c.addToGroup(id, {'tags'});
      expect(c.groupOf('tags')?.id, id);
      expect(c.marked, isEmpty);

      expect(c.updateGroup(id, (g) => g.copyWith(name: 'B')), isTrue);
      expect(c.groups.single.name, 'B');
      expect(c.updateGroup('nope', (g) => g), isFalse);
    });

    test('a table leaving its only group removes the empty group', () {
      final id = c.createGroup(
          tables: {'users'}, tableNames: names, name: 'A');
      c.removeFromGroup('users');
      expect(c.groups, isEmpty);
      c.createGroup(tables: {'users'}, tableNames: names, name: 'A');
      c.ungroup(c.groups.single.id);
      expect(c.groups, isEmpty);
      expect(id, isNotEmpty);
    });

    test('allGroups adds one group per schema when there are several', () {
      final schema = ErdSchema(tables: [
        for (final n in ['a.users', 'a.orders', 'b.logs'])
          ErdTable(name: n, columns: const []),
      ], relations: const []);
      final all = c.allGroups(schema);
      expect(all.length, greaterThan(c.groups.length));
      expect(c.allGroups(null), isEmpty);
    });
  });

  group('marks, density, colours', () {
    test('toggleMarked marks and unmarks', () {
      c.toggleMarked('users');
      expect(c.marked, {'users'});
      c.toggleMarked('users');
      expect(c.marked, isEmpty);
    });

    test('hiding a table drops its mark and a pick on it', () {
      c.marked.addAll({'users', 'tags'});
      c.selected = 'users';
      c.hide('users');
      expect(c.hidden, {'users'});
      expect(c.marked, {'tags'});
      expect(c.selected, isNull);

      c.selected = 'tags';
      c.hide('items');
      expect(c.selected, 'tags');
    });

    test('collapsing toggles; a header colour is set and reset', () {
      c.toggleCollapsed('users');
      expect(c.collapsed, {'users'});
      c.toggleCollapsed('users');
      expect(c.collapsed, isEmpty);
      c.setHeaderColor('users', 'type2');
      expect(c.headerColors['users'], 'type2');
      c.setHeaderColor('users', null);
      expect(c.headerColors, isEmpty);
    });

    test('applying a saved state replaces density, groups and notes; colours '
        'only when asked', () {
      c.headerColors['users'] = 'type1';
      c.notes.add(const ErdNote(id: 'n9', text: 'old', x: 0, y: 0));
      const saved = ErdSavedLayout(
        collapsed: {'orders'},
        hidden: {'tags'},
        detail: ErdDetail.keys,
        headerColors: {'orders': 'type3'},
        notes: [ErdNote(id: 'n1', text: 'new', x: 1, y: 2)],
      );
      c.applyState(saved, colours: false);
      expect(c.collapsed, {'orders'});
      expect(c.hidden, {'tags'});
      expect(c.detail, ErdDetail.keys);
      expect(c.notes.single.id, 'n1');
      expect(c.headerColors, {'users': 'type1'});

      c.applyState(saved, colours: true);
      expect(c.headerColors, {'orders': 'type3'});
    });
  });

  group('notes', () {
    test('update, delete, move and resize find the note by id', () {
      c.addNote(const ErdNote(id: 'n1', text: 'a', x: 100, y: 100));
      expect(c.updateNote('n1', (n) => n.copyWith(text: 'b')), isTrue);
      expect(c.notes.single.text, 'b');
      expect(c.updateNote('zz', (n) => n), isFalse);

      c.moveNote('n1', const Offset(20, 40), 2); // zoom 2: half the canvas move
      expect(c.notes.single.x, 110);
      expect(c.notes.single.y, 120);
      c.resizeNote('n1', const Offset(40, 20), 2);
      expect(c.notes.single.width, ErdNote.defaultWidth + 20);
      c.moveNote('zz', const Offset(1, 1), 1);

      c.deleteNote('n1');
      expect(c.notes, isEmpty);
    });

    test('a note attached to a table follows it; a loose one stays', () {
      final schema = ErdSchema(tables: [
        for (final n in ['a', 'b']) ErdTable(name: n, columns: const []),
      ], relations: const []);
      final before = ErdLayout.compute(schema);
      final after = before.withPosition('a', before.positions['a']! + const Offset(30, 10));
      c.notes.addAll([
        const ErdNote(id: 'n1', text: '', x: 5, y: 5, attachedTo: 'a'),
        const ErdNote(id: 'n2', text: '', x: 5, y: 5),
      ]);
      c.followTables(before, after);
      expect(c.notes[0].x, 35);
      expect(c.notes[0].y, 15);
      expect(c.notes[1].x, 5);
    });

    test('the canvas grows to hold a note placed beyond the cards', () {
      const schema = ErdSchema(
          tables: [ErdTable(name: 'a', columns: [])], relations: []);
      final layout = ErdLayout.compute(schema);
      final plain = c.canvasSize(layout);
      expect(plain, layout.size);
      c.notes.add(const ErdNote(id: 'far', text: '', x: 5000, y: 4000));
      final grown = c.canvasSize(layout);
      expect(grown.width, 5000 + ErdNote.defaultWidth + ErdLayout.margin);
      expect(grown.height, 4000 + ErdNote.defaultHeight + ErdLayout.margin);
    });
  });

  group('saved views', () {
    ErdSavedView view(String id, String name) => ErdSavedView(
        id: id, name: name, tables: const {}, layout: const ErdSavedLayout());

    test('ids count up and fill a gap', () {
      expect(c.nextViewId(), 'v1');
      c.views.addAll([view('v1', 'A'), view('v3', 'C')]);
      expect(c.nextViewId(), 'v2');
    });

    test('rename and remove by id', () {
      c.views.add(view('v1', 'A'));
      expect(c.renameView('v1', 'Z'), isTrue);
      expect(c.viewById('v1')?.name, 'Z');
      expect(c.renameView('v9', 'Q'), isFalse);
      expect(c.viewById(null), isNull);
      c.removeView('v1');
      expect(c.views, isEmpty);
    });
  });

  group('picks and Esc', () {
    test('picking a table drops a picked relation and the other way round', () {
      const r = ErdRelation(
          fromTable: 'orders',
          fromColumn: 'user_id',
          toTable: 'users',
          toColumn: 'id');
      c.pickRelation(r);
      expect(c.pickedRelation, r);
      c.pick('users');
      expect(c.selected, 'users');
      expect(c.pickedRelation, isNull);
      c.pickRelation(r);
      expect(c.selected, isNull);
    });

    test('clearPicks says whether there was anything to clear', () {
      expect(c.clearPicks(), isFalse);
      c.marked.add('users');
      expect(c.clearPicks(), isTrue);
      expect(c.marked, isEmpty);
    });

    test('Esc takes one step per press, in order', () {
      const r = ErdRelation(
          fromTable: 'a', fromColumn: 'x', toTable: 'b', toColumn: 'y');
      c
        ..searchOpen = true
        ..query = 'ord'
        ..pickedRelation = r
        ..marked.add('a')
        ..selected = 'b';
      expect(c.escape(), ErdEscape.closedSearch);
      expect(c.query, isEmpty);
      expect(c.selected, 'b', reason: 'closing the search keeps the pick');
      expect(c.escape(), ErdEscape.droppedRelation);
      expect(c.escape(), ErdEscape.clearedMarks);
      expect(c.escape(), ErdEscape.clearedPick);
      expect(c.escape(), ErdEscape.nothing);
    });
  });

  group('focus', () {
    test('the dragged table beats the picked one, then the hovered one', () {
      expect(c.currentFocus('h'), 'h');
      c.selected = 's';
      expect(c.currentFocus('h'), 's');
      c.dragging = 'd';
      expect(c.currentFocus('h'), 'd');
    });

    test('a pick fades the cards that are not next to it', () {
      c.neighbours = {
        'users': {'orders'},
        'orders': {'users'},
        'tags': {},
      };
      expect(c.cardFocusFor('tags', null).faded, isFalse,
          reason: 'nothing is picked');
      c.selected = 'users';
      expect(c.cardFocusFor('orders', 'users').highlighted, isTrue);
      expect(c.cardFocusFor('tags', 'users').faded, isTrue);
    });

    test('a picked relation lights its two tables and names their columns',
        () {
      c.pickedRelation = const ErdRelation(
          fromTable: 'orders',
          fromColumn: 'user_id',
          toTable: 'users',
          toColumn: 'id');
      final from = c.cardFocusFor('orders', null);
      expect(from.highlighted, isTrue);
      expect(from.column, 'user_id');
      expect(c.cardFocusFor('users', null).column, 'id');
      final other = c.cardFocusFor('tags', null);
      expect(other.faded, isTrue);
      expect(other.column, isNull);
    });
  });

  group('saving and views', () {
    const here = Offset(10, 20);

    test('a snapshot copies the state with the positions and the viewport', () {
      c
        ..collapsed.add('users')
        ..hidden.add('tags')
        ..detail = ErdDetail.keys
        ..headerColors['users'] = 'type2';
      final snap = c.snapshot(
          positions: {'users': here}, scale: 1.5, translation: const Offset(3, 4));
      expect(snap.positions, {'users': here});
      expect(snap.collapsed, {'users'});
      expect(snap.hidden, {'tags'});
      expect(snap.detail, ErdDetail.keys);
      expect(snap.scale, 1.5);
      expect(snap.translation, const Offset(3, 4));

      // A copy: later changes do not reach it.
      c.collapsed.add('orders');
      expect(snap.collapsed, {'users'});
    });

    test('with no active view the snapshot becomes the diagram own state', () {
      final snap = c.snapshot(positions: {}, scale: 1, translation: Offset.zero);
      c.capture(snap, names);
      expect(c.base, same(snap));
    });

    test('with a view active the snapshot goes to that view, tables minus hidden',
        () {
      final id = c.addViewFromCurrent(
        name: 'Sales',
        current: c.snapshot(positions: {}, scale: 1, translation: Offset.zero),
        tableNames: names,
      );
      c.hidden.add('tags');
      final snap = c.snapshot(
          positions: {'users': here}, scale: 2, translation: Offset.zero);
      c.capture(snap, names);
      final view = c.viewById(id)!;
      expect(view.layout.positions, {'users': here});
      expect(view.tables, {'users', 'orders', 'items'});
      expect(view.name, 'Sales');
    });

    test('a new view from All tables shows every table there afterwards', () {
      c.hidden.add('tags');
      c.base = c.snapshot(positions: {}, scale: 1, translation: Offset.zero);
      final id = c.addViewFromCurrent(
        name: 'Core',
        current: c.snapshot(positions: {}, scale: 1, translation: Offset.zero),
        tableNames: names,
      );
      expect(c.activeView, id);
      expect(c.base.hidden, isEmpty, reason: 'All tables always shows all');
      expect(c.viewById(id)!.tables, isNot(contains('tags')));
    });

    test('stateOfView: null is All tables, an id is its view, a stranger is none',
        () {
      expect(c.stateOfView(null, names.toSet()), same(c.base));
      final id = c.addViewFromCurrent(
        name: 'V',
        current: c.snapshot(positions: {}, scale: 1, translation: Offset.zero),
        tableNames: names,
      );
      expect(c.stateOfView(id, names.toSet()), isNotNull);
      expect(c.stateOfView('v99', names.toSet()), isNull);
    });

    test('toStore carries the views, the active one and the colours', () {
      c.headerColors['users'] = 'type4';
      final id = c.addViewFromCurrent(
        name: 'V',
        current: c.snapshot(positions: {}, scale: 1, translation: Offset.zero),
        tableNames: names,
      );
      final stored = c.toStore();
      expect(stored.views.single.id, id);
      expect(stored.activeView, id);
      expect(stored.headerColors, {'users': 'type4'});
    });
  });
}
