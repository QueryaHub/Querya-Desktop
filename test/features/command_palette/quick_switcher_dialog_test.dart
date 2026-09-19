import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/features/command_palette/quick_switcher_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  final seed = [
    QueryaSchemaObject.postgres(
      database: 'app',
      schema: 'public',
      name: 'users',
      kind: QueryaSchemaObjectKind.table,
    ),
    QueryaSchemaObject.postgres(
      database: 'app',
      schema: 'public',
      name: 'accounts',
      kind: QueryaSchemaObjectKind.view,
    ),
  ];

  Future<void> pumpSwitcher(
    WidgetTester tester, {
    required void Function(QueryaSchemaObject) onOpen,
    String initialQuery = '',
  }) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: QueryaCommandHost(
            onOpenSchemaObject: onOpen,
            child: Builder(
              builder: (context) {
                return Center(
                  child: Button.primary(
                    onPressed: () => showQuickSwitcher(
                      context,
                      initialQuery: initialQuery,
                      seed: seed,
                    ),
                    child: const Text('Open switcher'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open switcher'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('filters users and Enter opens public.users', (tester) async {
    QueryaSchemaObject? opened;
    await pumpSwitcher(tester, onOpen: (o) => opened = o);

    expect(find.text('Go to table, view, collection…'), findsOneWidget);
    expect(find.byKey(const ValueKey('pg:app:public:table:users')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'users');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('pg:app:public:table:users')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pg:app:public:view:accounts')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(opened?.qualifiedName, 'public.users');
    expect(find.text('Go to table, view, collection…'), findsNothing);
  });

  testWidgets('Escape closes without opening', (tester) async {
    var opened = 0;
    await pumpSwitcher(tester, onOpen: (_) => opened++);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text('Go to table, view, collection…'), findsNothing);
  });

  testWidgets('empty seed shows no-objects hint', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: Builder(
            builder: (context) {
              return Center(
                child: Button.primary(
                  onPressed: () => showQuickSwitcher(
                    context,
                    seed: const [],
                  ),
                  child: const Text('Open switcher'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open switcher'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No objects in the active connection'), findsOneWidget);
  });
}
