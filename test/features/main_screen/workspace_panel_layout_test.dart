import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/motion/querya_switching_body.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/workspace_panel.dart';
import 'package:querya_desktop/features/redis/redis_explorer_view.dart';
import 'package:querya_desktop/features/redis/redis_view.dart';

import '../../support/layout_overflow.dart';
import '../../support/querya_theme_test_shell.dart';

void main() {
  /// Not a real DB driver; exercises the honest unsupported state.
  const stubSplitWorkspaceConnection = ConnectionRow(
    id: 1,
    type: '_layout_test_split',
    name: 'layout-stub',
    host: '127.0.0.1',
    port: 0,
    createdAt: '0',
  );

  const redisConnection = ConnectionRow(
    id: 42,
    type: 'redis',
    name: 'redis-test',
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
            queryaThemeTestShell(
              child: const material.SizedBox.expand(
                child: WorkspacePanel(),
              ),
            ),
          );
        });
      });
    }

    testWidgets('unsupported connection state does not overflow',
        (tester) async {
      await expectNoLayoutOverflow(() async {
        await pumpWidgetWithSurfaceSize(
          tester,
          const material.Size(800, 600),
          queryaThemeTestShell(
            child: const material.SizedBox.expand(
              child: WorkspacePanel(
                  activeConnection: stubSplitWorkspaceConnection),
            ),
          ),
        );
      });

      expect(find.text('Unsupported connection type'), findsOneWidget);
      expect(find.textContaining('_layout_test_split'), findsOneWidget);
    });

    testWidgets('Execute button hidden when no active connection',
        (tester) async {
      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(),
          ),
        ),
      );

      expect(
          find.byKey(const material.Key('workspace_run_button')), findsNothing);
      expect(find.text('Execute/Refresh (F5)'), findsNothing);
    });

    testWidgets('dead query controls are absent for unsupported connections',
        (tester) async {
      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(
              activeConnection: stubSplitWorkspaceConnection,
            ),
          ),
        ),
      );

      expect(
          find.byKey(const material.Key('workspace_run_button')), findsNothing);
      expect(find.text('Query History'), findsNothing);
      expect(find.textContaining('Coming in a future release'), findsNothing);
    });

    testWidgets('empty↔connected morph uses QueryaSwitchingBody',
        (tester) async {
      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(),
          ),
        ),
      );
      expect(find.byType(QueryaSwitchingBody), findsWidgets);

      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(
              activeConnection: stubSplitWorkspaceConnection,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(QueryaSwitchingBody), findsWidgets);
      expect(find.text('Unsupported connection type'), findsOneWidget);

      // Back to empty — keep-alive stack stays mounted.
      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QueryaSwitchingBody), findsWidgets);
    });
  });

  group('WorkspacePanel home↔object morph', () {
    testWidgets('Redis stats↔explorer uses SwitchingBody + FadeSlide',
        (tester) async {
      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(activeConnection: redisConnection),
          ),
        ),
      );
      await tester.pump();

      // Outer empty↔connected + inner home↔object (+ hero FadeSlide keep-alive).
      expect(find.byType(QueryaSwitchingBody), findsNWidgets(2));
      expect(find.byType(QueryaFadeSlide), findsWidgets);
      expect(find.byType(RedisView), findsOneWidget);

      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(
              activeConnection: redisConnection,
              selectedRedisDb: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(QueryaSwitchingBody), findsNWidgets(2));
      expect(find.byType(QueryaFadeSlide), findsWidgets);
      expect(find.byType(RedisExplorerView), findsOneWidget);
      // Home stays keep-alive under SwitchingBody.
      expect(find.byType(RedisView), findsOneWidget);

      await pumpWidgetWithSurfaceSize(
        tester,
        const material.Size(800, 600),
        queryaThemeTestShell(
          child: const material.SizedBox.expand(
            child: WorkspacePanel(activeConnection: redisConnection),
          ),
        ),
      );
      // Avoid pumpAndSettle — Redis stats polling keeps a ticker alive.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(RedisView), findsOneWidget);
      expect(find.byType(QueryaSwitchingBody), findsNWidgets(2));
    });
  });
}
