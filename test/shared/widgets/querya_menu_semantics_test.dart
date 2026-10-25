import 'package:flutter/material.dart' as material;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';
import 'package:querya_desktop/shared/widgets/querya_menu_bar.dart';

import '../../support/querya_theme_test_shell.dart';

/// How many semantics nodes carry [label] (#1815): a screen reader stops on
/// each of them, so a menu title must be one node, not two.
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
  testWidgets('each menu bar title is one semantics node (#1815)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMenuBar(
          children: [
            QueryaMenuItem(
              subMenu: [
                QueryaMenuItem(onTap: () {}, child: const material.Text('Open')),
              ],
              child: const material.Text('File'),
            ),
            QueryaMenuItem(
              subMenu: [
                QueryaMenuItem(onTap: () {}, child: const material.Text('Copy')),
              ],
              child: const material.Text('Edit'),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(_nodesLabelled(tester, 'File'), 1);
    expect(_nodesLabelled(tester, 'Edit'), 1);
    handle.dispose();
  });

  testWidgets('each context menu item is one semantics node (#1815)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Center(
          child: QueryaContextMenu(
            items: [
              QueryaMenuItem(onTap: () {}, child: const material.Text('Copy Value')),
              QueryaMenuItem(
                  onTap: () {}, child: const material.Text('Copy with Headers')),
            ],
            child: const material.SizedBox(
                width: 200, height: 100, child: material.Text('target')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('target'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(_nodesLabelled(tester, 'Copy Value'), 1);
    expect(_nodesLabelled(tester, 'Copy with Headers'), 1);
    handle.dispose();
  });
}
