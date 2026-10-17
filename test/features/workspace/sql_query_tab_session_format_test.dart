import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';

void main() {
  tearDown(UnsavedWorkRegistry.instance.resetForTest);

  test('Format SQL keeps the caret and the selection (#1566)', () {
    final session = SqlQueryTabSession(
      id: '1',
      title: 'Q',
      customController: TextEditingController(),
    );
    addTearDown(session.dispose);

    session.controller.value = const TextEditingValue(
      text: "select a from t where b = 'or'",
      selection: TextSelection(baseOffset: 7, extentOffset: 8),
    );
    session.formatSql();

    expect(session.controller.text, "SELECT a FROM t WHERE b = 'or'");
    expect(
      session.controller.selection,
      const TextSelection(baseOffset: 7, extentOffset: 8),
    );
  });
}
