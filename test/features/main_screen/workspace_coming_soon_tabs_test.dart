import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/workspace_panel.dart';

import '../../support/querya_theme_test_shell.dart';

ConnectionRow _stubConnection({required String type}) => ConnectionRow(
      id: 1,
      type: type,
      name: 'Stub',
      createdAt: '2026-01-01T00:00:00.000Z',
    );

void main() {
  testWidgets('placeholder tabs render coming soon state', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 900,
          height: 700,
          child: WorkspacePanel(
            activeConnection: _stubConnection(type: '_layout_test_split'),
          ),
        ),
      ),
    );

    expect(find.text('Query History'), findsWidgets);
    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Notifications'), findsWidgets);
    expect(find.textContaining('Coming in a future release'), findsNWidgets(3));
    expect(find.byIcon(material.Icons.hourglass_empty_rounded), findsNWidgets(3));
  });
}
