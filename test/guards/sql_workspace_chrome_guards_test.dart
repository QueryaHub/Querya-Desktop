import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The bars around the SQL editor are one visual system (#1558): they take
/// their colours from the workbench tokens, and no two controls of the row
/// share an icon.
void main() {
  const chrome = [
    'lib/features/workspace/sql_query_tab_bar.dart',
    'lib/features/workspace/sql_workspace_toolbar.dart',
    'lib/features/workspace/sql_editor_chrome.dart',
  ];

  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('the SQL pane chrome uses workbench tokens, not the shadcn scheme', () {
    for (final path in chrome) {
      final source = code(path);
      expect(source.contains('colorScheme'), isFalse,
          reason: '$path reads Theme.colorScheme: use context.workbench.');
      expect(RegExp(r'Color\(0x').hasMatch(source), isFalse,
          reason: '$path has a raw colour: use a theme token.');
    }
  });

  test('Explain and the Diagram button do not share an icon', () {
    final toolbar = code('lib/features/workspace/sql_workspace_toolbar.dart');
    final workspace = code('lib/features/workspace/generic_sql_workspace.dart');
    final explain = RegExp(
      r"ValueKey\('explain_query'\)[\s\S]*?icon: material\.Icons\.(\w+)",
    ).firstMatch(toolbar)?.group(1);
    final diagram = RegExp(
      r"ValueKey\('open_diagram_tab'\)[\s\S]*?icon: material\.Icons\.(\w+)",
    ).firstMatch(workspace)?.group(1);

    expect(explain, isNotNull);
    expect(diagram, isNotNull);
    expect(explain, isNot(diagram));
  });

  test('the tab strip and the toolbar share one surface decoration', () {
    expect(code('lib/features/workspace/sql_query_tab_bar.dart'),
        contains('SqlEditorChrome.sqlToolbarDecoration'));
    expect(code('lib/features/workspace/generic_sql_workspace.dart'),
        contains('SqlEditorChrome.sqlToolbarDecoration'));
  });
}
