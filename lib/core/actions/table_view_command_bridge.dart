import 'package:flutter/foundation.dart';

/// Lets the Command Palette switch the table browser on screen between Data
/// and Relations. Only a table that offers the switch registers.
class TableViewCommandBridge {
  TableViewCommandBridge._();

  static final TableViewCommandBridge instance = TableViewCommandBridge._();

  Object? _owner;
  void Function(int index)? _onSelectView;

  bool get isActive => _onSelectView != null;

  void register({
    required Object owner,
    required void Function(int index) onSelectView,
  }) {
    _owner = owner;
    _onSelectView = onSelectView;
  }

  /// Clears the registration only while [owner] still holds it, so a table
  /// that closes does not drop the one that registered after it.
  void unregister({required Object owner}) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _onSelectView = null;
  }

  /// 0 shows the grid (Data), 1 the neighbourhood (Relations).
  void invokeSelectView(int index) => _onSelectView?.call(index);

  @visibleForTesting
  void resetForTest() {
    _owner = null;
    _onSelectView = null;
  }
}
