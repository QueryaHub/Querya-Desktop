import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';

void main() {
  tearDown(SqlEditorCommandBridge.instance.resetForTest);

  test('register invokes pending new query after mount', () {
    final bridge = SqlEditorCommandBridge.instance;
    bridge.queuePending(SqlEditorPendingAction.newQuery);

    var newCount = 0;
    bridge.register(
      connectionId: 1,
      onNew: () => newCount++,
      onOpen: () {},
      onSave: () {},
    );

    expect(newCount, 1);
    expect(bridge.pendingAction, SqlEditorPendingAction.none);
  });

  test('invokeOpen uses active handler when registered', () {
    final bridge = SqlEditorCommandBridge.instance;
    var openCount = 0;
    bridge.register(
      connectionId: 2,
      onNew: () {},
      onOpen: () => openCount++,
      onSave: () {},
    );

    bridge.invokeOpen();
    expect(openCount, 1);
  });

  test('unregister ignores stale connection id', () {
    final bridge = SqlEditorCommandBridge.instance;
    var newCount = 0;
    bridge.register(
      connectionId: 3,
      onNew: () => newCount++,
      onOpen: () {},
      onSave: () {},
    );

    bridge.unregister(connectionId: 99);
    expect(bridge.isActive, isTrue);

    bridge.unregister(connectionId: 3);
    expect(bridge.isActive, isFalse);
  });
}
