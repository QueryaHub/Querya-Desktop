import 'package:flutter/material.dart' as material;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/environment_section.dart';
import 'package:querya_desktop/features/connections/forms/connection_auth_section.dart';
import 'package:querya_desktop/features/connections/forms/connection_host_port_section.dart';

import '../../support/querya_theme_test_shell.dart';

int _nodesLabelled(WidgetTester tester, String label) {
  var count = 0;
  void visit(SemanticsNode node) {
    if (node.label.split('\n').first.trim() == label) count++;
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return count;
}

void main() {
  testWidgets('host, port, user and password fields carry their caption '
      'and the password has one show button (#1822)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SingleChildScrollView(
          child: material.Column(
            children: [
              ConnectionHostPortSection(
                hostController: material.TextEditingController(),
                portController: material.TextEditingController(),
              ),
              ConnectionAuthSection(
                usernameController: material.TextEditingController(),
                passwordController: material.TextEditingController(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final label in ['Host', 'Port', 'Username', 'Password']) {
      final labelled = find.semantics.byLabel(label);
      expect(labelled, findsWidgets, reason: label);
    }
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.byTooltip('Show'), findsNothing);
    handle.dispose();
  });

  testWidgets('an environment option is one semantics node (#1822)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: EnvironmentSection(value: null, onChanged: (_) {}),
      ),
    );
    await tester.pump();

    expect(_nodesLabelled(tester, 'None'), 1);
    handle.dispose();
  });
}
