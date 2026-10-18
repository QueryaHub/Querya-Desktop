import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Epic #1465: `package:shadcn_flutter` is leaving `lib/`. A ratchet: the files
/// below still import it and may; no other file may start to, and a file
/// that drops the import leaves the list in the same change.
///
/// `Gap` is the `gap` package's own (#1729): the barrel exports it directly
/// and a file that imports shadcn without a prefix hides shadcn's copy.
void main() {
  const allowed = <String>{
    'lib/core/editor/querya_code_editor.dart',
    'lib/features/mongodb/mongo_document_tree_view.dart',
    'lib/features/mongodb/mongo_documents_json_view.dart',
    'lib/features/mongodb/mongo_documents_table_view.dart',
    'lib/features/settings/preferences_controls.dart',
    'lib/features/workspace/data_grid_calc_bar.dart',
    'lib/features/workspace/data_grid_filter_bar.dart',
    'lib/features/workspace/data_grid_value_panel.dart',
    'lib/features/workspace/grid_cell_editor.dart',
    'lib/features/workspace/result_grid_view.dart',
    'lib/features/workspace/sql_editor_chrome.dart',
    'lib/shared/widgets/widgets.dart',
  };

  final importsShadcn = RegExp('package:shadcn_flutter/');

  Map<String, String> sources() => {
        for (final e in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart'))
            e.path.replaceAll(r'\', '/'): e.readAsStringSync(),
      };

  test('no new file imports shadcn_flutter', () {
    final importing = {
      for (final MapEntry(:key, :value) in sources().entries)
        if (importsShadcn.hasMatch(value)) key,
    };
    expect(importing.difference(allowed), isEmpty,
        reason: 'New shadcn imports: use the kit or Flutter (#1465).');
    expect(allowed.difference(importing), isEmpty,
        reason: 'These no longer import shadcn: take them off the list.');
  });

  test('Gap comes from the gap package, not through shadcn', () {
    final shadcnImport = RegExp(
        r"import 'package:shadcn_flutter/shadcn_flutter\.dart'([^;]*);");
    final offenders = <String>[];
    for (final MapEntry(:key, :value) in sources().entries) {
      final m = shadcnImport.firstMatch(value);
      if (m == null) continue;
      final spec = m.group(1)!;
      // A prefixed import or a `show` list brings no unprefixed Gap.
      if (spec.contains(' as ')) continue;
      if (RegExp(r'\bshow\b').hasMatch(spec) &&
          !RegExp(r'\bGap\b').hasMatch(spec)) {
        continue;
      }
      if (!RegExp(r'hide [^;]*\bGap\b').hasMatch(spec)) offenders.add(key);
    }
    expect(offenders, isEmpty,
        reason: 'Import shadcn with `hide Gap` and take Gap from package:gap.');
  });

  test('text inputs are QueryaTextField, not shadcn TextField (#1733)', () {
    final shadcnField = RegExp(r'(?<![\w.])TextField\(|\bInputFeature\.');
    final offenders = <String>[
      for (final MapEntry(:key, :value) in sources().entries)
        if (key != 'lib/shared/widgets/querya_text_field.dart' &&
            shadcnField.hasMatch(value))
          key,
    ];
    expect(offenders, isEmpty,
        reason: 'Use QueryaTextField (the barrel hides shadcn TextField).');
  });

  test('no hand-built material TextField outside the kit (#1733)', () {
    const kit = {
      'lib/shared/widgets/querya_text_field.dart',
      'lib/shared/widgets/querya_search_field.dart',
    };
    final offenders = <String>[
      for (final MapEntry(:key, :value) in sources().entries)
        if (!kit.contains(key) && value.contains('material.TextField('))
          key,
    ];
    expect(offenders, isEmpty,
        reason: 'Use QueryaTextField (framed: false inside a frame of your own).');
  });
}
