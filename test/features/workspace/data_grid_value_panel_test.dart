import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_value_panel.dart';
import 'package:querya_desktop/features/workspace/xml_html_formatter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('XmlHtmlFormatter', () {
    test('validates correct XML tags', () {
      expect(XmlHtmlFormatter.validate('<root><child>value</child></root>'), isNull);
      expect(XmlHtmlFormatter.validate('<img src="test.png" />'), isNull);
      expect(XmlHtmlFormatter.validate('<br>'), isNull);
    });

    test('detects mismatched or unclosed XML tags', () {
      expect(XmlHtmlFormatter.validate('<root><child></root>'), isNotNull);
      expect(XmlHtmlFormatter.validate('<root><child>'), isNotNull);
      expect(XmlHtmlFormatter.validate('</root>'), isNotNull);
    });

    test('pretty prints XML with indentation', () {
      const input = '<root><user id="1"><name>Alice</name></user></root>';
      final formatted = XmlHtmlFormatter.format(input);
      expect(formatted, contains('  <user id="1">'));
      expect(formatted, contains('    <name>'));
      expect(formatted, contains('      Alice'));
      expect(formatted, contains('    </name>'));
    });

    test('minifies XML by collapsing whitespace', () {
      const input = '''
<root>
  <user>
    Alice
  </user>
</root>
''';
      final minified = XmlHtmlFormatter.minify(input);
      expect(minified, contains('<root><user> Alice </user></root>'));
    });
  });

  group('DataGridValuePanel Widget', () {
    testWidgets('renders panel with initial JSON and formatting buttons', (tester) async {
      String? updatedVal;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridValuePanel(
              columnName: 'payload',
              cellValue: '{"name":"John","age":30}',
              rowIndex: 0,
              onClose: () {},
              onUpdateValue: (val) => updatedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('payload [Row 1]'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Minify'), findsOneWidget);

      await tester.tap(find.text('Update Cell Value'));
      await tester.pumpAndSettle();
      expect(updatedVal, isNotNull);
    });

    testWidgets('debounces validation parsing on text input changes', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridValuePanel(
              columnName: 'json_col',
              cellValue: '{"valid":true}',
              rowIndex: 0,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no validation error
      expect(find.textContaining('Invalid JSON'), findsNothing);

      // Enter invalid JSON (trailing comma) into editor
      await tester.enterText(find.byType(material.TextField), '{"invalid": true,}');
      await tester.pump(const Duration(milliseconds: 50));
      // Before 150ms debounce fires, error is not yet shown
      expect(find.textContaining('Invalid JSON'), findsNothing);

      // Advance clock past 150ms debounce
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Invalid JSON'), findsOneWidget);
    });

    testWidgets('preserves compact JSON formatting when opened and saved', (tester) async {
      String? updatedVal;
      const initialJson = '{"name":"John","age":30}';

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridValuePanel(
              columnName: 'payload',
              cellValue: initialJson,
              rowIndex: 0,
              onClose: () {},
              onUpdateValue: (val) => updatedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Controller should retain compact single line
      final textField = tester.widget<material.TextField>(find.byType(material.TextField));
      expect(textField.controller!.text, initialJson);
      expect(find.text('Preserve compact formatting'), findsOneWidget);

      // Tap Format - text in editor becomes indented
      await tester.tap(find.text('Format'));
      await tester.pumpAndSettle();
      expect(textField.controller!.text, contains('\n'));

      // Save while "Preserve compact formatting" is checked -> saved value is compacted
      await tester.tap(find.text('Update Cell Value'));
      await tester.pumpAndSettle();
      expect(updatedVal, '{"name":"John","age":30}');

      // Now uncheck "Preserve compact formatting" and save -> saved value is formatted
      await tester.tap(find.text('Preserve compact formatting'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update Cell Value'));
      await tester.pumpAndSettle();
      expect(updatedVal, contains('\n'));
    });

    testWidgets('blocks saving when validation error exists or on immediate invalid submit', (tester) async {
      String? updatedVal;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridValuePanel(
              columnName: 'payload',
              cellValue: '{"valid":true}',
              rowIndex: 0,
              onClose: () {},
              onUpdateValue: (val) => updatedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter broken JSON and immediately click Update Cell Value before debounce
      await tester.enterText(find.byType(material.TextField), '{"broken":');
      await tester.tap(find.text('Update Cell Value'));
      await tester.pumpAndSettle();

      // Should not have updated
      expect(updatedVal, isNull);
      // Error banner should be displayed immediately
      expect(find.textContaining('Invalid JSON'), findsOneWidget);

      // Elevated button is now disabled because _validationError != null
      final button = tester.widget<material.ElevatedButton>(find.byType(material.ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });
}
