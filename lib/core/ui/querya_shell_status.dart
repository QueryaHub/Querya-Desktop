import 'package:flutter/foundation.dart';

/// Global shell metrics for [QueryaStatusBar] (busy, last query, grid size).
///
/// SQL workspaces and other long-running UI paths publish here; [MainScreen]
/// listens and forwards into the status bar. Cleared on connection switch.
class QueryaShellStatus extends ChangeNotifier {
  QueryaShellStatus._();

  static final QueryaShellStatus instance = QueryaShellStatus._();

  bool _isBusy = false;
  String? _statusMessage;
  int? _rowCount;
  int? _columnCount;
  Duration? _lastQueryDuration;

  bool get isBusy => _isBusy;
  String? get statusMessage => _statusMessage;
  int? get rowCount => _rowCount;
  int? get columnCount => _columnCount;
  Duration? get lastQueryDuration => _lastQueryDuration;

  /// Marks the shell busy (spinner + optional message).
  void beginBusy({String? message}) {
    _isBusy = true;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  /// Clears busy; keeps last query metrics unless [clearMetrics] is true.
  void endBusy({bool clearMetrics = false}) {
    _isBusy = false;
    if (clearMetrics) {
      _statusMessage = null;
      _rowCount = null;
      _columnCount = null;
      _lastQueryDuration = null;
    }
    notifyListeners();
  }

  /// Publishes a completed query (or command) and clears busy.
  void reportQueryResult({
    Duration? duration,
    int? rowCount,
    int? columnCount,
    String? message,
  }) {
    _isBusy = false;
    if (duration != null) _lastQueryDuration = duration;
    if (rowCount != null) _rowCount = rowCount;
    if (columnCount != null) _columnCount = columnCount;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  /// Clears busy + metrics (e.g. connection switch).
  void clear() {
    _isBusy = false;
    _statusMessage = null;
    _rowCount = null;
    _columnCount = null;
    _lastQueryDuration = null;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() => clear();
}
