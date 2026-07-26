import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:querya_desktop/shared/widgets/app_dialog.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('read-only badge visual baseline', (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(220, 48));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.Center(
          child: QueryaReadOnlyBadge(),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(QueryaReadOnlyBadge),
      matchesGoldenFile('goldens/title_bar_read_only_badge.png'),
    );
  });

  testWidgets('tab strip visual baseline', (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(520, 64));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Center(
          child: material.SizedBox(
            width: 480,
            child: QueryaTabStrip(
              labels: const ['Server', 'SQL', 'History'],
              selectedIndex: 1,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    // Wait for post-frame indicator layout + spring settle.
    await tester.pump();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(QueryaTabStrip),
      matchesGoldenFile('goldens/querya_tab_strip.png'),
    );
  });

  testWidgets('app dialog visual baseline', (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(640, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late material.BuildContext ctx;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) {
            ctx = context;
            return const material.SizedBox.expand(
              child: material.ColoredBox(
                color: material.Color(0xFF1A1B1E),
                child: material.Center(
                  child: material.Text('Workspace'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final future = showAppDialog<void>(
      context: ctx,
      builder: (dialogContext) => material.AlertDialog(
        title: const material.Text('Confirm action'),
        content: const material.SizedBox(
          width: 280,
          child: material.Text('This dialog uses the shared Querya overlay.'),
        ),
        actions: [
          material.TextButton(
            onPressed: () => material.Navigator.of(dialogContext).pop(),
            child: const material.Text('Cancel'),
          ),
          material.TextButton(
            onPressed: () => material.Navigator.of(dialogContext).pop(),
            child: const material.Text('Confirm'),
          ),
        ],
      ),
    );

    // Advance past the overlay enter animation without waiting forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(ShadcnApp),
      matchesGoldenFile('goldens/app_dialog_overlay.png'),
    );

    material.Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await future;
  });
}
