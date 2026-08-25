import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/data_grid_value_panel.dart';
import 'package:querya_desktop/features/main_screen/xml_html_formatter.dart';

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
  });
}
