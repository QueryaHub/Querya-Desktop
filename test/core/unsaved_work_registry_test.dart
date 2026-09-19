import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';

void main() {
  tearDown(UnsavedWorkRegistry.instance.resetForTest);

  test('SqlQueryTabSession registers modified SQL as unsaved', () {
    final session = SqlQueryTabSession(id: '1', title: 'Q');
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isFalse);

    session.isModified = true;
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isTrue);

    session.dispose();
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isFalse);
  });
}
