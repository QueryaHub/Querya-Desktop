import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// Polish from the ER diagram interface review: the plain note, keys after a
/// note was touched, the views menu, the grouping hint, the mark on a card.
class _MemoryStore implements ErdLayoutStore {
  _MemoryStore([this.initial]);

  final ErdSavedLayout? initial;
  final layouts = <ErdLayoutKey, ErdSavedLayout>{};

  @override
  Future<ErdSavedLayout?> read(ErdLayoutKey key) async =>
      layouts[key] ?? initial;

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

final _note = find.byKey(const material.ValueKey('erd_note_n1'));
const _plainNote = ErdSavedLayout(notes: [
  ErdNote(id: 'n1', text: 'Plain', x: 40, y: 300),
]);

void main() {
  final desktop = TargetPlatformVariant.only(material.TargetPlatform.linux);

  Future<void> pumpDiagram(
    WidgetTester t,
    _MemoryStore store, {
    material.Widget? above,
  }) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final view = ErdView(
      source: SqlErdSource(delegate: _catalog(), dialect: SqlDialect.sqlite),
      layoutStore: store,
      layoutKey: _key,
    );
    await t.pumpWidget(queryaThemeTestShell(
      child: above == null
          ? view
          : material.Column(children: [above, material.Expanded(child: view)]),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
  }

  testWidgets('a plain note is not the canvas colour and has a shadow',
      (t) async {
    await pumpDiagram(t, _MemoryStore(_plainNote));
    final box = t.widget<material.DecoratedBox>(find
        .descendant(of: _note, matching: find.byType(material.DecoratedBox))
        .first);
    final decoration = box.decoration as material.BoxDecoration;
    final surface = t.element(_note).workbench.surface;
    expect(decoration.color, isNot(surface));
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('keys work after a note was touched while focus was elsewhere',
      (t) async {
    final outside = material.FocusNode();
    addTearDown(outside.dispose);
    await pumpDiagram(
      t,
      _MemoryStore(_plainNote),
      above: material.Focus(
          focusNode: outside, child: const material.SizedBox(height: 4)),
    );
    String zoom() => t
        .widget<material.Text>(
            find.byKey(const material.ValueKey('erd_zoom_label')))
        .data!;
    final fitted = zoom();
    await t.tap(find.byKey(const material.ValueKey('erd_zoom_in')));
    await t.pump();
    expect(zoom(), isNot(fitted));

    // The keyboard is somewhere else (another pane, a closed dialog).
    outside.requestFocus();
    await t.pump();
    expect(outside.hasPrimaryFocus, isTrue);
    await t.tap(_note);
    await t.pump(const Duration(milliseconds: 400));
    expect(outside.hasPrimaryFocus, isFalse);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit0);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(zoom(), fitted);
  });

  testWidgets('a long view name is cut in the toolbar', variant: desktop,
      (t) async {
    await pumpDiagram(t, _MemoryStore());
    await t.tap(find.byKey(const material.ValueKey('erd_views')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save as new view…'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    const long = 'Billing and invoicing, payments and refunds by month';
    await t.enterText(
        find.byKey(const material.ValueKey('erd_view_name')), long);
    await t.pump();
    await t.tap(find.byKey(const material.ValueKey('erd_view_submit')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(long), findsNothing);
    expect(find.text('${long.substring(0, 27)}…'), findsOneWidget);
  });

  testWidgets('a card menu says how to group more tables', variant: desktop,
      (t) async {
    await pumpDiagram(t, _MemoryStore());
    await t.tap(find.byKey(const material.ValueKey('erd_table_users')),
        buttons: kSecondaryButton);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('New group…'), findsOneWidget);
    expect(find.textContaining('Shift+click'), findsOneWidget);
  });

  testWidgets('a marked card keeps its border and gets a ring outside',
      variant: desktop, (t) async {
    await pumpDiagram(t, _MemoryStore());
    final card = find.byKey(const material.ValueKey('erd_table_users'));
    material.BoxDecoration decoration() => t
        .widget<material.Container>(find
            .descendant(of: card, matching: find.byType(material.Container))
            .first)
        .decoration as material.BoxDecoration;
    final plain = decoration();
    expect(plain.boxShadow!.any((s) => s.spreadRadius > 0), isFalse);

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(card);
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final marked = decoration();
    final border = marked.border! as material.Border;
    expect(border.top.width, (plain.border! as material.Border).top.width);
    expect(marked.boxShadow!.any((s) => s.spreadRadius > 0), isTrue);
  });
}
