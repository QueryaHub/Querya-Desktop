import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/main_screen/workspace_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/layout_overflow.dart';

void main() {
  const stubRedisConnection = ConnectionRow(
    id: 1,
    type: 'redis',
    name: 'layout-stub',
    host: '127.0.0.1',
    port: 6379,
    createdAt: '0',
  );

  group('WorkspacePanel layout (no connection)', () {
    final sizes = <String, material.Size>{
      'narrow_tall': const material.Size(320, 720),
      'very_narrow': const material.Size(280, 560),
      'medium': const material.Size(900, 640),
      'wide_short': const material.Size(1280, 480),
      'large': const material.Size(1440, 900),
    };

    for (final entry in sizes.entries) {
      testWidgets('no layout overflow at ${entry.key} ${entry.value}',
          (tester) async {
        await expectNoLayoutOverflow(() async {
          await pumpWidgetWithSurfaceSize(
            tester,
            entry.value,
            ShadcnApp(
              theme: AppTheme.dark,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.dark,
              home: const material.SizedBox.expand(
                child: WorkspacePanel(),
              ),
            ),
          );
        });
      });
    }

    testWidgets('resize splitter does not overflow', (tester) async {
      await expectNoLayoutOverflow(() async {
        await pumpWidgetWithSurfaceSize(
          tester,
          const material.Size(800, 600),
          ShadcnApp(
            theme: AppTheme.dark,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const material.SizedBox.expand(
              child: WorkspacePanel(activeConnection: stubRedisConnection),
            ),
          ),
        );
      });

      final handle = find.byKey(const Key('workspace_panel_resize_handle'));
      expect(handle, findsOneWidget);

      await expectNoLayoutOverflow(() async {
        await tester.drag(handle, const Offset(0, 80));
        await tester.pumpAndSettle();
      });

      await expectNoLayoutOverflow(() async {
        await tester.drag(handle, const Offset(0, -120));
        await tester.pumpAndSettle();
      });
    });
  });
}
