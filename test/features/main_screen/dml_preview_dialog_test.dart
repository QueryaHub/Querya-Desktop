import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/main_screen/dml_preview_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  material.Widget buildTestDialog({required TableMutationPlan plan, void Function(bool?)? onResult}) {
    return queryaThemeTestShell(
      child: material.Material(
        child: material.Builder(
          builder: (context) {
            return OutlineButton(
              onPressed: () async {
                final res = await showDmlPreviewDialog(context: context, plan: plan);
                onResult?.call(res);
              },
              child: const Text('Open Dialog'),
            );
          },
        ),
      ),
    );
  }

  group('DmlPreviewConfirmationDialog', () {
    const samplePlan = TableMutationPlan(
      dialect: SqlDialect.postgres,
      tableName: 'users',
      schema: 'public',
      statements: const [
        TableMutationStatement(
          type: MutationType.update,
          sql: 'UPDATE "public"."users" SET "name" = \'Alice\' WHERE "id" = 1',
          description: 'Update row 1',
        ),
        TableMutationStatement(
          type: MutationType.insert,
          sql: 'INSERT INTO "public"."users" ("id", "name") VALUES (2, \'Bob\')',
          description: 'Insert new row 2',
        ),
        TableMutationStatement(
          type: MutationType.delete,
          sql: 'DELETE FROM "public"."users" WHERE "id" = 3',
          description: 'Delete row 3',
        ),
      ],
    );

    testWidgets('renders dialog header, badges, and SQL preview', (tester) async {
      await tester.pumpWidget(buildTestDialog(plan: samplePlan));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Data Changes'), findsOneWidget);
      expect(find.text('public.users'), findsOneWidget);
      expect(find.text('PostgreSQL'), findsOneWidget);
      expect(find.text('1 UPDATE'), findsOneWidget);
      expect(find.text('1 INSERT'), findsOneWidget);
      expect(find.text('1 DELETE'), findsOneWidget);
      expect(find.text('Apply Changes'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('BEGIN;'), findsOneWidget);
      expect(find.textContaining('COMMIT;'), findsOneWidget);
    });

    testWidgets('cancelling dialog pops false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        buildTestDialog(
          plan: samplePlan,
          onResult: (res) => result = res,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('confirming dialog pops true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        buildTestDialog(
          plan: samplePlan,
          onResult: (res) => result = res,
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Changes'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });
}
