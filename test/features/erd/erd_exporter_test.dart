import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' as material;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_router.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';
import 'package:querya_desktop/features/erd/erd_exporter.dart';
import 'package:querya_desktop/features/erd/widgets/erd_export_menu.dart';

/// #1362: the export flows no longer live in the view state, so they can be
/// driven with a fake source.
class _FakeSource implements ErdExportSource {
  final saved = <String, String>{};

  @override
  material.BuildContext get exportContext => throw UnimplementedError();

  @override
  bool get exportMounted => true;

  @override
  String get fileStem => 'shop-erd';

  @override
  Future<void> saveFile(String name, Uint8List bytes) async {
    saved[name] = utf8.decode(bytes);
  }

  @override
  List<ErdRoute> get routes => const [];

  @override
  List<ErdGroup> get groups => const [];

  @override
  List<ErdNote> get notes => const [];

  @override
  Map<String, String> get headerColorSlots => const {};

  @override
  material.Color slotColor(String slot) => const material.Color(0xFF123456);

  @override
  material.Size canvasSize(ErdLayout layout) => layout.size;

  @override
  ErdSvgColors currentThemeColors() => const ErdSvgColors();

  @override
  Map<String, String> headerFills(ErdSchema schema, String cardHex) =>
      const {};

  @override
  List<ErdSvgGroup> svgGroups(ErdLayout layout, String backgroundHex) =>
      const [];

  @override
  List<ErdSvgNote> svgNotes(ErdSvgColors colors) => const [];

  @override
  RenderRepaintBoundary? get canvasBoundary => null;

  @override
  Future<void> withCleanCanvas(Future<void> Function() capture) => capture();
}

void main() {
  const schema = ErdSchema(
    tables: [
      ErdTable(name: 'users', columns: [
        ErdColumn(name: 'id', type: 'integer', isPrimaryKey: true),
      ]),
      ErdTable(name: 'orders', columns: [
        ErdColumn(name: 'id', type: 'integer', isPrimaryKey: true),
        ErdColumn(name: 'user_id', type: 'integer', isForeignKey: true),
      ]),
    ],
    relations: [
      ErdRelation(
        fromTable: 'orders',
        fromColumn: 'user_id',
        toTable: 'users',
        toColumn: 'id',
      ),
    ],
  );

  test('Mermaid is saved as <stem>.mmd', () async {
    final source = _FakeSource();
    final layout = ErdLayout.compute(schema);

    ErdExporter(source).export(ErdExportAction.mermaid, schema, layout);
    await Future<void>.delayed(Duration.zero);

    expect(source.saved.keys, ['shop-erd.mmd']);
    expect(source.saved['shop-erd.mmd'], contains('erDiagram'));
  });

  test('DBML is saved as <stem>.dbml and names the tables', () async {
    final source = _FakeSource();
    final layout = ErdLayout.compute(schema);

    ErdExporter(source).export(ErdExportAction.dbml, schema, layout);
    await Future<void>.delayed(Duration.zero);

    final dbml = source.saved['shop-erd.dbml']!;
    expect(dbml, contains('Table "users"'));
    expect(dbml, contains('Table "orders"'));
    expect(dbml, contains('Ref: "orders"."user_id" > "users"."id"'));
  });

  test('dbml() leaves out groups of tables that are not shown', () {
    final exporter = ErdExporter(_FakeSource());

    expect(exporter.dbml(schema), isNot(contains('TableGroup')));
  });
}
