import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/theme/querya_semantic_palette.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/shared/widgets/connection_environment_badge.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

/// The theme values the components should be using at the moment.
class _Captured {
  _Captured(this.workbench, this.palette, this.foreground);
  final QueryaWorkbenchTheme workbench;
  final QueryaSemanticPalette palette;
  final material.Color foreground;
}

void main() {
  _Captured? captured;

  /// One tree holding a sample of every themed UI Kit component. The same
  /// widget instances are rebuilt when the theme changes, as in the app.
  const kit = _UiKitSample();

  Future<void> pumpKit(WidgetTester tester, QueryaTheme theme) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        data: theme,
        child: material.Scaffold(
          body: material.Builder(
            builder: (context) {
              captured = _Captured(
                context.workbench,
                context.semanticPalette,
                Theme.of(context).colorScheme.foreground,
              );
              return kit;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  material.Color? textColor(WidgetTester tester, String text) =>
      tester.widget<material.Text>(find.text(text)).style?.color;

  material.Color? iconColor(WidgetTester tester, material.IconData icon) =>
      material.IconTheme.of(tester.element(find.byIcon(icon))).color;

  material.Color spinnerColor(WidgetTester tester) => tester
      .widget<material.CircularProgressIndicator>(
        find.byType(material.CircularProgressIndicator),
      )
      .valueColor!
      .value!;

  /// Asserts every sampled component uses the colors of the active theme.
  void expectThemed(WidgetTester tester) {
    final wb = captured!.workbench;
    final palette = captured!.palette;

    expect(spinnerColor(tester), wb.accent, reason: 'spinner');

    expect(textColor(tester, 'Connected'), wb.success, reason: 'success badge');
    expect(textColor(tester, 'Failed'), wb.destructive, reason: 'error badge');
    expect(textColor(tester, 'Beta'), wb.warning, reason: 'warning badge');
    expect(textColor(tester, 'PK'), palette.type1, reason: 'primary key');
    expect(textColor(tester, 'FK'), palette.type2, reason: 'foreign key');

    expect(textColor(tester, 'PROD'), wb.destructive, reason: 'environment');
    expect(textColor(tester, 'STAGING'), wb.warning, reason: 'environment');
    expect(textColor(tester, 'DEV'), wb.success, reason: 'environment');

    expect(iconColor(tester, material.Icons.star_rounded), wb.accent,
        reason: 'active icon button');
    expect(iconColor(tester, material.Icons.delete_rounded), wb.destructive,
        reason: 'destructive active icon button');
    expect(iconColor(tester, material.Icons.add_rounded), captured!.foreground,
        reason: 'plain icon button');

    expect(textColor(tester, 'Nothing here yet'), wb.mutedForeground,
        reason: 'empty state description');
  }

  group('themes used by the test', () {
    test('dark and light differ, so a switch is observable', () {
      expect(
        QueryaTheme.darkDefault.workbench.canvas,
        isNot(QueryaTheme.lightDefault.workbench.canvas),
      );
      expect(
        QueryaTheme.darkDefault.workbench.mutedForeground,
        isNot(QueryaTheme.lightDefault.workbench.mutedForeground),
      );
    });
  });

  group('UI Kit follows the active theme', () {
    testWidgets('dark theme', (tester) async {
      await pumpKit(tester, QueryaTheme.darkDefault);

      expectThemed(tester);
    });

    testWidgets('light theme', (tester) async {
      await pumpKit(tester, QueryaTheme.lightDefault);

      expectThemed(tester);
    });

    testWidgets('switching dark -> light updates every component in place',
        (tester) async {
      await pumpKit(tester, QueryaTheme.darkDefault);
      final darkMuted = textColor(tester, 'Nothing here yet');
      expectThemed(tester);

      await pumpKit(tester, QueryaTheme.lightDefault);

      expectThemed(tester);
      expect(textColor(tester, 'Nothing here yet'), isNot(darkMuted),
          reason: 'muted text changed with the theme');
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching light -> dark and back is stable', (tester) async {
      await pumpKit(tester, QueryaTheme.lightDefault);
      await pumpKit(tester, QueryaTheme.darkDefault);
      expectThemed(tester);

      await pumpKit(tester, QueryaTheme.lightDefault);
      expectThemed(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('component state survives a theme switch', (tester) async {
      await pumpKit(tester, QueryaTheme.darkDefault);
      await tester.enterText(find.byType(material.TextField), 'orders');
      await tester.pump();

      await pumpKit(tester, QueryaTheme.lightDefault);

      expect(find.text('orders'), findsOneWidget);
    });
  });
}

class _UiKitSample extends material.StatelessWidget {
  const _UiKitSample();

  @override
  material.Widget build(material.BuildContext context) {
    return const material.SingleChildScrollView(
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          QueryaSpinner(size: QueryaSpinnerSize.md),
          QueryaBadge.status('Connected', status: QueryaBadgeStatus.success),
          QueryaBadge.status('Failed', status: QueryaBadgeStatus.error),
          QueryaBadge.status('Beta', status: QueryaBadgeStatus.warning),
          QueryaBadge.primaryKey(),
          QueryaBadge.foreignKey(),
          ConnectionEnvironmentBadge(
            environment: ConnectionEnvironment.production,
          ),
          ConnectionEnvironmentBadge(
            environment: ConnectionEnvironment.staging,
          ),
          ConnectionEnvironmentBadge(
            environment: ConnectionEnvironment.development,
          ),
          material.Row(
            children: [
              QueryaIconButton(
                icon: material.Icon(material.Icons.star_rounded),
                isActive: true,
                onPressed: _noop,
              ),
              QueryaIconButton(
                icon: material.Icon(material.Icons.delete_rounded),
                isActive: true,
                isDestructive: true,
                onPressed: _noop,
              ),
              QueryaIconButton(
                icon: material.Icon(material.Icons.add_rounded),
                onPressed: _noop,
              ),
            ],
          ),
          material.SizedBox(
            width: 300,
            height: 220,
            child: QueryaEmptyState(
              title: 'Empty',
              description: 'Nothing here yet',
              icon: material.Icon(material.Icons.inbox_rounded),
            ),
          ),
          material.SizedBox(width: 300, child: QueryaSearchField()),
        ],
      ),
    );
  }
}

void _noop() {}
