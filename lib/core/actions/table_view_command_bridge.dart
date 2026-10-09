import 'package:flutter/foundation.dart';

/// Lets the Command Palette switch the table browser on screen between Data
/// and Relations. Only a table that offers the switch registers.
class TableViewCommandBridge {
  TableViewCommandBridge._();

  static final TableViewCommandBridge instance = TableViewCommandBridge._();

  Object? _owner;
  void Function(int index)? _onSelectView;
  int? _pendingView;
  DateTime? _pendingAt;

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

  /// Asks the next table browser that opens to start in view [index]
  /// ("Show relations", or walking the graph from a Relations view). A request
  /// older than a few seconds is dropped, so a table that did not open does
  /// not change a later one.
  void requestViewForNextTable(int index) {
    _pendingView = index;
    _pendingAt = DateTime.now();
  }

  /// The view asked for by [requestViewForNextTable], once.
  int? takePendingView() {
    final view = _pendingView, at = _pendingAt;
    _pendingView = null;
    _pendingAt = null;
    if (view == null || at == null) return null;
    return DateTime.now().difference(at) < const Duration(seconds: 3)
        ? view
        : null;
  }

  @visibleForTesting
  void resetForTest() {
    _owner = null;
    _onSelectView = null;
    _pendingView = null;
    _pendingAt = null;
  }
}
