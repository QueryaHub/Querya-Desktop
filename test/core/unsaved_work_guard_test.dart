import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/core/unsaved_work_guard.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  tearDown(UnsavedWorkRegistry.instance.resetForTest);

  testWidgets('returns true immediately when nothing is unsaved',
      (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
        home: const material.Scaffold(body: material.SizedBox()),
      ),
    );
    final ctx = tester.element(find.byType(material.Scaffold));
    expect(await confirmDiscardUnsavedWorkIfNeeded(ctx), isTrue);
  });

  testWidgets(
    'dirty buffer + Home/Close does not dispose until Discard is confirmed',
    (tester) async {
      final buffer = DataGridStagingBuffer(
        columns: const ['id'],
        rows: const [
          ['1'],
        ],
      );
      buffer.setCell(0, 0, '2');
      expect(UnsavedWorkRegistry.instance.hasUnsaved, isTrue);

      var navigated = false;
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: material.Builder(
            builder: (context) {
              return material.TextButton(
                onPressed: () async {
                  if (!await confirmDiscardUnsavedWorkIfNeeded(context)) {
                    return;
                  }
                  buffer.dispose();
                  navigated = true;
                },
                child: const material.Text('Home'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(navigated, isFalse);
      expect(UnsavedWorkRegistry.instance.hasUnsaved, isTrue);
      expect(find.text('Discard'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(navigated, isFalse);
      expect(buffer.isDirty, isTrue);
      expect(UnsavedWorkRegistry.instance.hasUnsaved, isTrue);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(navigated, isTrue);
      expect(UnsavedWorkRegistry.instance.hasUnsaved, isFalse);
    },
  );
}
