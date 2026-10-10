import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

/// #1284: saved diagram views.
void main() {
  const billing = ErdSavedView(
    id: 'v1',
    name: 'Billing',
    tables: {'orders', 'payments', 'gone'},
    layout: ErdSavedLayout(
      positions: {
        'orders': Offset(10, 20),
        'payments': Offset(300, 20),
        'gone': Offset(5, 5),
      },
      collapsed: {'payments'},
      detail: ErdDetail.keys,
      scale: 0.5,
      translation: Offset(-40, 12),
      groups: [
        ErdGroup(
            id: 'g1', name: 'Money', color: 'type2', tables: ['orders', 'gone']),
      ],
      notes: [ErdNote(id: 'n1', text: 'hi', x: 1, y: 2)],
    ),
  );

  test('views and the active one come back from JSON', () {
    final back = ErdSavedLayout.decode(
        const ErdSavedLayout(views: [billing], activeView: 'v1').encode())!;
    final v = back.views.single;
    expect((v.id, v.name), ('v1', 'Billing'));
    expect(v.tables, {'orders', 'payments', 'gone'});
    expect(v.layout.detail, ErdDetail.keys);
    expect(v.layout.collapsed, {'payments'});
    expect(v.layout.positions['payments'], const Offset(300, 20));
    expect(v.layout.scale, 0.5);
    expect(v.layout.groups.single.name, 'Money');
    expect(v.layout.notes.single.text, 'hi');
    expect(back.activeView, 'v1');
    expect(const ErdSavedLayout(views: [billing]).isEmpty, isFalse);
  });

  test('an unknown active view and broken or duplicate views are dropped', () {
    final back = ErdSavedLayout.decode('{"activeView": "zzz", "views": ['
        '{"id": "a", "name": "A", "tables": ["t"], "layout": {}},'
        '{"id": "a", "name": "Dup", "tables": ["t"], "layout": {}},'
        '{"id": "b", "name": "", "tables": ["t"], "layout": {}},'
        '{"id": "c", "name": "C", "layout": {}},'
        '{"id": "d", "name": "D", "tables": ["t"]}'
        ']}')!;
    expect([for (final v in back.views) v.name], ['A']);
    expect(back.activeView, isNull);
  });

  test('a dropped table leaves every view that listed it', () {
    final kept = const ErdSavedLayout(views: [billing], activeView: 'v1')
        .keepOnly({'orders', 'payments', 'users'});
    final v = kept.views.single;
    expect(v.tables, {'orders', 'payments'});
    expect(v.layout.positions.keys, {'orders', 'payments'});
    expect(v.layout.groups.single.tables, ['orders']);
    expect(kept.activeView, 'v1');
  });

  test('a view applies as a layout hiding what it does not list', () {
    final layout = billing.asLayout(
        {'orders', 'payments', 'users', 'logs'}, const {'users': 'type1'});
    expect(layout.hidden, {'users', 'logs'});
    expect(layout.collapsed, {'payments'});
    expect(layout.headerColors, {'users': 'type1'});
    expect(layout.views, isEmpty);
  });

  test('showingAll keeps the arrangement and hides nothing', () {
    const state = ErdSavedLayout(
      positions: {'a': Offset(1, 2)},
      hidden: {'b'},
      collapsed: {'a'},
      detail: ErdDetail.names,
    );
    final all = state.showingAll();
    expect(all.hidden, isEmpty);
    expect(all.positions, state.positions);
    expect(all.collapsed, {'a'});
    expect(all.detail, ErdDetail.names);
  });
}
