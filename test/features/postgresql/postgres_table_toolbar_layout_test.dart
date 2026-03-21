import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_toolbar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/layout_overflow.dart';

PostgresTableToolbar _toolbar({
  required String title,
  bool customSqlActive = false,
  bool isMaterializedView = false,
  bool loading = false,
}) {
  return PostgresTableToolbar(
    title: title,
    paginationLabel: 'Rows 1–50 of 200',
    tableIcon: material.Icons.table_chart_rounded,
    customSqlActive: customSqlActive,
    isMaterializedView: isMaterializedView,
    loading: loading,
    canGoPrevious: true,
    canGoNext: true,
    onOpenSql: () {},
    onOpenPrivileges: () {},
    onRefreshMaterializedView: () {},
    onExitCustomMode: () {},
    onGoPrevious: () {},
    onGoNext: () {},
    onRefresh: () {},
  );
}

void main() {
  group('PostgresTableToolbar', () {
    final sizes = <String, material.Size>{
      'narrow': const material.Size(360, 120),
      'medium': const material.Size(720, 120),
      'wide': const material.Size(1200, 120),
    };

    for (final entry in sizes.entries) {
      testWidgets('no overflow at ${entry.key} with long title', (tester) async {
        await expectNoLayoutOverflow(() async {
          await pumpWidgetWithSurfaceSize(
            tester,
            entry.value,
            ShadcnApp(
              theme: AppTheme.dark,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.dark,
              home: material.Scaffold(
                body: _toolbar(
                  title:
                      'public.this_is_a_very_long_schema_and_table_name_that_should_ellipsis_not_overflow',
                ),
              ),
            ),
          );
        });
      });
    }

    testWidgets('materialized view extra button — narrow', (tester) async {
      await expectNoLayoutOverflow(() async {
        await pumpWidgetWithSurfaceSize(
          tester,
          const material.Size(400, 140),
          ShadcnApp(
            theme: AppTheme.dark,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: material.Scaffold(
              body: _toolbar(
                title: 'mv_schema.long_materialized_view_name',
                isMaterializedView: true,
              ),
            ),
          ),
        );
      });
    });

    testWidgets('custom SQL mode — narrow', (tester) async {
      await expectNoLayoutOverflow(() async {
        await pumpWidgetWithSurfaceSize(
          tester,
          const material.Size(400, 140),
          ShadcnApp(
            theme: AppTheme.dark,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: material.Scaffold(
              body: _toolbar(
                title: 'custom query',
                customSqlActive: true,
              ),
            ),
          ),
        );
      });
    });
  });
}
