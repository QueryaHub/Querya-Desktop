import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/shared/widgets/ssl_certificate_fields.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('Connection Dialogs Focus Traversal', () {
    testWidgets('NewConnectionUrlDialog contains FocusTraversalGroups with WidgetOrderTraversalPolicy', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showNewConnectionUrlDialog(context),
              child: const material.Text('Open URL Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open URL Dialog'));
      await tester.pumpAndSettle();

      final widgetOrderGroups = tester
          .widgetList<material.FocusTraversalGroup>(
            find.byType(material.FocusTraversalGroup),
          )
          .where((g) => g.policy is material.WidgetOrderTraversalPolicy)
          .toList();

      expect(widgetOrderGroups.length, greaterThanOrEqualTo(2));
    });

    testWidgets('showPostgresConnectionForm contains FocusTraversalGroups with WidgetOrderTraversalPolicy', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showPostgresConnectionForm(context),
              child: const material.Text('Open Postgres Form'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Postgres Form'));
      await tester.pumpAndSettle();

      final widgetOrderGroups = tester
          .widgetList<material.FocusTraversalGroup>(
            find.byType(material.FocusTraversalGroup),
          )
          .where((g) => g.policy is material.WidgetOrderTraversalPolicy)
          .toList();

      expect(widgetOrderGroups.length, greaterThanOrEqualTo(3));
    });

    testWidgets('SslCertificateFields is wrapped in FocusTraversalGroup with WidgetOrderTraversalPolicy', (tester) async {
      final rootCertCtrl = TextEditingController();
      final clientCertCtrl = TextEditingController();
      final clientKeyCtrl = TextEditingController();

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SslCertificateFields(
              rootCertController: rootCertCtrl,
              clientCertController: clientCertCtrl,
              clientKeyController: clientKeyCtrl,
            ),
          ),
        ),
      );

      final traversalGroup = find.descendant(
        of: find.byType(SslCertificateFields),
        matching: find.byType(material.FocusTraversalGroup),
      );
      expect(traversalGroup, findsOneWidget);

      final groupWidget = tester.widget<material.FocusTraversalGroup>(traversalGroup);
      expect(groupWidget.policy, isA<material.WidgetOrderTraversalPolicy>());
    });
  });
}
