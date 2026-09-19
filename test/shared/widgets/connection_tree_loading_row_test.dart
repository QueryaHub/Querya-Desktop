import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';
import 'package:querya_desktop/shared/widgets/connection_tree_loading_row.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  test('QueryaTreeTokens exposes named indent levels', () {
    expect(QueryaTreeTokens.indent, 16);
    expect(QueryaTreeTokens.underConnection, 20);
    expect(QueryaTreeTokens.leafList, 26);
    expect(QueryaTreeTokens.errorConnection, 28);
    expect(QueryaTreeTokens.errorNested, 24);
    expect(QueryaTreeTokens.errorPaddingForDepth(2).left, 36 + 2 * 16);
  });

  testWidgets('ConnectionTreeLoadingRow.connection uses connection spinner',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const ConnectionTreeLoadingRow.connection(),
      ),
    );

    expect(find.text('Loading...'), findsOneWidget);
    final indicator = tester.widget<material.CircularProgressIndicator>(
      find.byType(material.CircularProgressIndicator),
    );
    expect(indicator.strokeWidth, QueryaTreeTokens.spinnerStroke);
    final box = tester.widget<material.SizedBox>(
      find.ancestor(
        of: find.byType(material.CircularProgressIndicator),
        matching: find.byType(material.SizedBox),
      ),
    );
    expect(box.width, QueryaTreeTokens.spinnerConnection);
  });

  testWidgets('ConnectionTreeLoadingRow.nested uses nested spinner',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const ConnectionTreeLoadingRow.nested(),
      ),
    );

    final box = tester.widget<material.SizedBox>(
      find.ancestor(
        of: find.byType(material.CircularProgressIndicator),
        matching: find.byType(material.SizedBox),
      ),
    );
    expect(box.width, QueryaTreeTokens.spinnerNested);
  });
}
