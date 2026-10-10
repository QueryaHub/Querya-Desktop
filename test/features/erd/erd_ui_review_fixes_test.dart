import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// Fixes from the ER diagram interface review: the PNG capture, Fit with
/// notes, the neutral note outline in exports.
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

const _columns = [
  ['users', 'id', 'INTEGER', '1'],
  ['orders', 'user_id', 'INTEGER', '0'],
];
const _fks = [
  ['orders', 'user_id', 'users', 'id'],
];

FakeSqlExecutionDelegate _catalog() =>
    FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
        return const SqlExecutionResult(rows: _columns);
      }
      return const SqlExecutionResult(rows: _fks);
    });

void main() {
  tearDown(() => AppSettings.exportCurrentThemeOverride = null);

  Future<void> pumpDiagram(
    WidgetTester t,
    _MemoryStore store, {
    Future<void> Function(String, Uint8List)? onSave,
  }) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(
      child: ErdView(
        key: material.UniqueKey(),
        source: SqlErdSource(delegate: _catalog(), dialect: SqlDialect.sqlite),
        layoutStore: store,
        layoutKey: _key,
        onSaveFile: onSave,
      ),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
  }

  testWidgets('Fit brings a note placed far from the cards into view',
      (t) async {
    final store = _MemoryStore(const ErdSavedLayout(notes: [
      ErdNote(id: 'n1', text: 'Far away', x: 2600, y: 1800),
    ]));
    await pumpDiagram(t, store);
    final rect = t.getRect(find.byKey(const material.ValueKey('erd_note_n1')));
    const surface = material.Rect.fromLTWH(0, 0, 1200, 800);
    expect(surface.contains(rect.topLeft), isTrue, reason: '$rect');
    expect(surface.contains(rect.bottomRight), isTrue, reason: '$rect');
  });

  testWidgets(
      'the PNG capture has no picked relation or marks, and they come back',
      variant: TargetPlatformVariant.only(material.TargetPlatform.linux),
      (t) async {
    AppSettings.exportCurrentThemeOverride = () async => true;
    final saved = <String, Uint8List>{};
    var focusDuring = true, groupButtonDuring = true;
    final focus =
        find.byKey(const material.ValueKey('erd_focus_column_users_id'));
    final groupButton = find.byKey(const material.ValueKey('erd_group_marked'));
    await pumpDiagram(t, _MemoryStore(), onSave: (name, bytes) async {
      saved[name] = bytes;
      focusDuring = focus.evaluate().isNotEmpty;
      groupButtonDuring = groupButton.evaluate().isNotEmpty;
    });

    // Pick the relation by a click on its edge.
    final schema = ErdSchema.fromCatalog(columnRows: _columns, fkRows: _fks);
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
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: material.Offset.zero);
    await mouse.moveTo(onEdge);
    await mouse.down(onEdge);
    await mouse.up();
    await t.pump(const Duration(milliseconds: 400));
    // And mark a table for a group.
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(find.byKey(const material.ValueKey('erd_table_orders')));
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(focus, findsOneWidget);
    expect(groupButton, findsOneWidget);

    await t.tap(find.byKey(const material.ValueKey('erd_export')));
    await t.pumpAndSettle();
    await t.tap(find.text('PNG'));
    for (var i = 0; i < 60 && !saved.containsKey('erd.png'); i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect(saved['erd.png'], isNotNull);
    expect(focusDuring, isFalse, reason: 'the picked relation was in the PNG');
    expect(groupButtonDuring, isFalse, reason: 'the marks were in the PNG');
    await t.pump();
    expect(focus, findsOneWidget);
    expect(groupButton, findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a neutral note outline follows the export palette',
      (t) async {
    final saved = <String, Uint8List>{};
    final store = _MemoryStore(const ErdSavedLayout(notes: [
      ErdNote(id: 'n1', text: 'Plain', x: 40, y: 400),
    ]));

    Future<String> exportSvg() async {
      saved.clear();
      await pumpDiagram(t, store, onSave: (n, b) async => saved[n] = b);
      await t.tap(find.byKey(const material.ValueKey('erd_export')));
      await t.pumpAndSettle();
      await t.tap(find.text('SVG'));
      for (var i = 0; i < 40 && !saved.containsKey('erd.svg'); i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      await t.pump(const Duration(seconds: 1));
      return utf8.decode(saved['erd.svg']!);
    }

    String stroke(String svg) => RegExp(r'class="erd-note"[^>]* stroke="([^"]+)"')
        .firstMatch(svg)!
        .group(1)!;

    AppSettings.exportCurrentThemeOverride = () async => false;
    expect(stroke(await exportSvg()), '#cbd5e1');

    AppSettings.exportCurrentThemeOverride = () async => true;
    final themed = stroke(await exportSvg());
    // The dark test theme's border, not the light palette's.
    expect(themed, isNot('#cbd5e1'));
    expect(themed, matches(RegExp(r'^#[0-9a-f]{6}$')));
  });
}
