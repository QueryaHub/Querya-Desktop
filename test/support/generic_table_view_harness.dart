import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/workspace/generic_table_view.dart';

import 'fake_table_data_delegate.dart';
import 'querya_theme_test_shell.dart';

/// Pumps a [GenericTableView] backed by [delegate] and waits for the first
/// page to load.
Future<GenericTableViewState> pumpGenericTableView(
  WidgetTester tester,
  FakeTableDataDelegate delegate, {
  SqlDialect dialect = SqlDialect.postgres,
  bool isReadOnly = false,
  bool isView = false,
  bool showRelations = true,
  int limit = 200,
}) async {
  await tester.binding.setSurfaceSize(const material.Size(1300, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    queryaThemeTestShell(
      child: material.Scaffold(
        body: material.SizedBox.expand(
          child: GenericTableView(
            delegate: delegate,
            title: 'users',
            dialect: dialect,
            tableName: 'users',
            schema: 'public',
            isReadOnly: isReadOnly,
            isView: isView,
            showRelations: showRelations,
            limit: limit,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<GenericTableViewState>(find.byType(GenericTableView));
}
