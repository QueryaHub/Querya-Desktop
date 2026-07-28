import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('PreferencesCheckboxRow toggles without CheckboxListTile',
      (tester) async {
    var value = false;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.StatefulBuilder(
            builder: (context, setState) {
              return PreferencesCheckboxRow(
                value: value,
                title: const Text('Toggle me').small(),
                subtitle: const Text('Hint').muted().xSmall(),
                onChanged: (v) => setState(() => value = v),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(material.CheckboxListTile), findsNothing);
    expect(find.byType(material.Checkbox), findsOneWidget);
    expect(tester.widget<material.Checkbox>(find.byType(material.Checkbox)).value,
        isFalse);

    await tester.tap(find.text('Toggle me'));
    await tester.pump();
    expect(value, isTrue);

    await tester.tap(find.byType(material.Checkbox));
    await tester.pump();
    expect(value, isFalse);
  });
}
