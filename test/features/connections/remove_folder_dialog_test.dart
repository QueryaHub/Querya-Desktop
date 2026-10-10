import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/remove_folder_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  Future<bool?> open(WidgetTester t, int count, String tap) async {
    bool? result;
    await t.pumpWidget(queryaThemeTestShell(
      child: material.Builder(
        builder: (context) => material.ElevatedButton(
          onPressed: () async => result = await confirmRemoveFolder(context,
              name: 'Team A', connectionCount: count),
          child: const material.Text('Open'),
        ),
      ),
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(find.text('Remove folder "Team A"?'), findsOneWidget);
    await t.tap(find.text(tap));
    await t.pumpAndSettle();
    return result;
  }

  testWidgets('names the folder and how many connections go with it',
      (t) async {
    await open(t, 3, 'Cancel');
  });

  testWidgets('Cancel keeps the folder', (t) async {
    expect(await open(t, 2, 'Cancel'), isFalse);
  });

  testWidgets('Remove folder confirms', (t) async {
    expect(await open(t, 1, 'Remove folder'), isTrue);
  });
}
