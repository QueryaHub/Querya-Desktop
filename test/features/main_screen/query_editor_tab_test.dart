import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/main_screen/query_editor_tab.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('QueryEditorTab applies fontSize to EditableText', (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
        home: const material.Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: QueryEditorTab(fontSize: 17),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(material.EditableText), findsOneWidget);
    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.style.fontSize, 17);
  });

  testWidgets('QueryEditorTab default fontSize is 13', (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
        home: const material.Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: QueryEditorTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.style.fontSize, 13);
  });
}
