import 'package:flutter/foundation.dart';

enum SqlEditorPendingAction { none, newQuery, openFile, saveFile }

/// Lets the active SQL workspace handle File menu commands when menu focus is
/// outside the editor subtree (e.g. title bar).
class SqlEditorCommandBridge {
  SqlEditorCommandBridge._();

  static final SqlEditorCommandBridge instance = SqlEditorCommandBridge._();

  int? _ownerConnectionId;
  VoidCallback? _onNew;
  VoidCallback? _onOpen;
  VoidCallback? _onSave;

  SqlEditorPendingAction pendingAction = SqlEditorPendingAction.none;

  bool get isActive => _onNew != null;

  void register({
    required int? connectionId,
    required VoidCallback onNew,
    required VoidCallback onOpen,
    required VoidCallback onSave,
  }) {
    _ownerConnectionId = connectionId;
    _onNew = onNew;
    _onOpen = onOpen;
    _onSave = onSave;
    _flushPending();
  }

  void unregister({required int? connectionId}) {
    if (_ownerConnectionId != connectionId) return;
    _ownerConnectionId = null;
    _onNew = null;
    _onOpen = null;
    _onSave = null;
  }

  void queuePending(SqlEditorPendingAction action) {
    pendingAction = action;
  }

  void invokeNew() {
    if (_onNew != null) {
      _onNew!();
      return;
    }
    pendingAction = SqlEditorPendingAction.newQuery;
  }

  void invokeOpen() {
    if (_onOpen != null) {
      _onOpen!();
      return;
    }
    pendingAction = SqlEditorPendingAction.openFile;
  }

  void invokeSave() {
    if (_onSave != null) {
      _onSave!();
      return;
    }
    pendingAction = SqlEditorPendingAction.saveFile;
  }

  void _flushPending() {
    final action = pendingAction;
    if (action == SqlEditorPendingAction.none) return;
    pendingAction = SqlEditorPendingAction.none;

    switch (action) {
      case SqlEditorPendingAction.none:
        break;
      case SqlEditorPendingAction.newQuery:
        _onNew?.call();
      case SqlEditorPendingAction.openFile:
        _onOpen?.call();
      case SqlEditorPendingAction.saveFile:
        _onSave?.call();
    }
  }

  @visibleForTesting
  void resetForTest() {
    _ownerConnectionId = null;
    _onNew = null;
    _onOpen = null;
    _onSave = null;
    pendingAction = SqlEditorPendingAction.none;
  }
}
