import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_shell_status.dart';
import 'package:querya_desktop/features/connections/environment_section.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';
import 'package:querya_desktop/features/main_screen/querya_status_bar.dart';
import 'package:querya_desktop/features/main_screen/safe_mode_unlock_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

ConnectionRow _conn(
  int id,
  String name, {
  ConnectionEnvironment? environment,
}) =>
    ConnectionRow(
      id: id,
      type: 'postgresql',
      name: name,
      host: '10.0.0.$id',
      port: 5432,
      createdAt: DateTime.utc(2026).toIso8601String(),
    ).withEnvironment(environment);

void main() {
  tearDown(QueryaShellStatus.instance.resetForTest);

  group('workspace state', () {
    test('a Production connection opens read-only', () {
      final ws = MainScreenWorkspaceState.empty
          .selectConnection(_conn(1, 'prod', environment: ConnectionEnvironment.production));
      expect(ws.isReadOnly, isTrue);
    });

    test('Development, Staging and untagged connections open writable', () {
      for (final env in [
        ConnectionEnvironment.development,
        ConnectionEnvironment.staging,
        null,
      ]) {
        final ws = MainScreenWorkspaceState.empty
            .selectConnection(_conn(1, 'db', environment: env));
        expect(ws.isReadOnly, isFalse, reason: '$env');
      }
    });

    test('switching from Production to a writable connection unlocks', () {
      final prod =
          _conn(1, 'prod', environment: ConnectionEnvironment.production);
      final ws = MainScreenWorkspaceState.empty
          .selectConnection(prod)
          .selectConnection(_conn(2, 'dev'));
      expect(ws.isReadOnly, isFalse);
    });

    test('re-selecting the same Production connection keeps an unlock', () {
      final prod =
          _conn(1, 'prod', environment: ConnectionEnvironment.production);
      final unlocked =
          MainScreenWorkspaceState.empty.selectConnection(prod).toggleReadOnly();
      expect(unlocked.isReadOnly, isFalse);
      expect(unlocked.selectConnection(prod).isReadOnly, isFalse);
    });

    test('selecting another Production connection locks again', () {
      final a = _conn(1, 'a', environment: ConnectionEnvironment.production);
      final b = _conn(2, 'b', environment: ConnectionEnvironment.production);
      final ws = MainScreenWorkspaceState.empty
          .selectConnection(a)
          .toggleReadOnly()
          .selectConnection(b);
      expect(ws.isReadOnly, isTrue);
    });
  });

  group('status bar badge', () {
    Future<void> pump(
      material.WidgetTester tester,
      ConnectionRow? connection,
    ) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaStatusBar(activeConnection: connection),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows PROD for Production', (tester) async {
      await pump(
        tester,
        _conn(1, 'orders', environment: ConnectionEnvironment.production),
      );
      expect(find.text('PROD'), findsOneWidget);
      expect(find.byKey(const material.Key('environment_badge_production')),
          findsOneWidget);
    });

    testWidgets('shows STAGING and DEV for those tags', (tester) async {
      await pump(
        tester,
        _conn(1, 'orders', environment: ConnectionEnvironment.staging),
      );
      expect(find.text('STAGING'), findsOneWidget);

      await pump(
        tester,
        _conn(2, 'orders', environment: ConnectionEnvironment.development),
      );
      expect(find.text('DEV'), findsOneWidget);
    });

    testWidgets('shows no badge for an untagged connection', (tester) async {
      await pump(tester, _conn(1, 'orders'));
      expect(find.text('PROD'), findsNothing);
      expect(find.text('STAGING'), findsNothing);
      expect(find.text('DEV'), findsNothing);
    });
  });

  group('EnvironmentSection', () {
    testWidgets('reports the chosen environment, and None clears it',
        (tester) async {
      ConnectionEnvironment? value = ConnectionEnvironment.staging;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.StatefulBuilder(
              builder: (context, setState) => EnvironmentSection(
                value: value,
                onChanged: (e) => setState(() => value = e),
              ),
            ),
          ),
        ),
      );

      await tester.tap(
          find.byKey(const material.Key('environment_option_production')));
      await tester.pump();
      expect(value, ConnectionEnvironment.production);
      expect(find.textContaining('Opens read-only'), findsOneWidget);

      await tester
          .tap(find.byKey(const material.Key('environment_option_none')));
      await tester.pump();
      expect(value, isNull);
      expect(find.textContaining('Opens read-only'), findsNothing);
    });
  });

  group('SafeModeUnlockDialog', () {
    Future<void> open(
      material.WidgetTester tester,
      void Function(bool) onResult,
    ) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.Scaffold(
              body: material.Center(
                child: material.TextButton(
                  onPressed: () async => onResult(
                    await showSafeModeUnlockDialog(
                      context: context,
                      connectionName: 'orders-prod',
                    ),
                  ),
                  child: const material.Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('unlock stays disabled until the name is typed',
        (tester) async {
      bool? result;
      await open(tester, (r) => result = r);

      final confirm =
          find.byKey(const material.Key('safe_mode_unlock_confirm'));
      expect(tester.widget<material.Widget>(confirm), isNotNull);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(result, isNull, reason: 'dialog must still be open');

      await tester.enterText(
          find.byKey(const material.Key('safe_mode_unlock_field')), 'wrong');
      await tester.pump();
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(result, isNull);

      await tester.enterText(
          find.byKey(const material.Key('safe_mode_unlock_field')),
          'orders-prod');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('cancel resolves to false', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
