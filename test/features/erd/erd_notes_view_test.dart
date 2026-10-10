import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// #1283: sticky notes added, edited, moved, attached, deleted, kept.
class _MemoryStore implements ErdLayoutStore {
  final layouts = <ErdLayoutKey, ErdSavedLayout>{};

  @override
  Future<ErdSavedLayout?> read(ErdLayoutKey key) async => layouts[key];

  @override
  Future<void> write(ErdLayoutKey key, ErdSavedLayout layout) async =>
      layouts[key] = layout;
}

const _key = ErdLayoutKey(connectionId: 1, scope: 'shop');

FakeSqlExecutionDelegate _catalog() =>
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

Finder _card(String table) =>
    find.byKey(material.ValueKey('erd_table_$table'));

final _note = find.byKey(const material.ValueKey('erd_note_n1'));

void main() {
  final desktop = TargetPlatformVariant.only(material.TargetPlatform.linux);

  Future<void> pumpDiagram(WidgetTester t, _MemoryStore store) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(
      child: ErdView(
        key: material.UniqueKey(),
        source: SqlErdSource(delegate: _catalog(), dialect: SqlDialect.sqlite),
        layoutStore: store,
        layoutKey: _key,
      ),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> addNote(WidgetTester t, String text) async {
    await t.tap(find.byKey(const material.ValueKey('erd_add_note')));
    await settle(t);
    await t.enterText(find.byKey(const material.ValueKey('erd_note_text')), text);
    await t.pump();
    await t.tap(find.byKey(const material.ValueKey('erd_note_submit')));
    await settle(t);
  }

  testWidgets('a note is added, edited, moved, resized and kept',
      variant: desktop, (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await addNote(t, 'Legacy, do not use');
    expect(_note, findsOneWidget);
    expect(find.text('Legacy, do not use'), findsOneWidget);

    final before = t.getTopLeft(_note);
    await t.drag(_note, const material.Offset(60, 30));
    await t.pump();
    final moved = t.getTopLeft(_note) - before;
    expect(moved.dx, greaterThan(20));

    final size = t.getSize(_note);
    final handle = find.byKey(const material.ValueKey('erd_note_resize_n1'));
    await t.drag(handle, const material.Offset(50, 40));
    await t.pump();
    expect(t.getSize(_note).width, greaterThan(size.width));

    await t.tap(_note, buttons: kSecondaryButton);
    await settle(t);
    await t.tap(find.byKey(const material.ValueKey('erd_note_edit_n1')));
    await settle(t);
    await t.enterText(
        find.byKey(const material.ValueKey('erd_note_text')), '**Filled** nightly');
    await t.pump();
    await t.tap(find.byKey(const material.ValueKey('erd_note_submit')));
    await settle(t);
    expect(find.text('Filled nightly'), findsOneWidget);

    await t.pump(const Duration(seconds: 1));
    final saved = store.layouts[_key]!.notes.single;
    expect(saved.text, '**Filled** nightly');
    expect(saved.width, greaterThan(200));

    await pumpDiagram(t, store);
    expect(_note, findsOneWidget);
    expect((t.getTopLeft(_note) - before).dx, closeTo(moved.dx, 1));
  });

  testWidgets('an attached note follows its table; delete removes it',
      variant: desktop, (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await addNote(t, 'Check the FK');

    await t.tap(_note, buttons: kSecondaryButton);
    await settle(t);
    await t.tap(find.byKey(const material.ValueKey('erd_note_attach_n1')));
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    final table = store.layouts[_key]!.notes.single.attachedTo;
    expect(table, isNotNull);

    final noteAt = t.getTopLeft(_note);
    final cardAt = t.getTopLeft(_card(table!));
    await t.drag(_card(table), const material.Offset(80, 50));
    await t.pump();
    await t.pump();
    final cardMoved = t.getTopLeft(_card(table)) - cardAt;
    final noteMoved = t.getTopLeft(_note) - noteAt;
    expect(cardMoved.dx, greaterThan(40));
    expect(noteMoved.dx, closeTo(cardMoved.dx, 0.01));
    expect(noteMoved.dy, closeTo(cardMoved.dy, 0.01));

    await t.tap(_note, buttons: kSecondaryButton);
    await settle(t);
    await t.tap(find.byKey(const material.ValueKey('erd_note_delete_n1')));
    await settle(t);
    expect(_note, findsNothing);
    await t.pump(const Duration(seconds: 1));
    expect(store.layouts[_key]!.notes, isEmpty);
  });
}
