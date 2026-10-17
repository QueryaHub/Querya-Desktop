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

  /// Whether [_statusMessage] only describes the running work ("Running
  /// query…"): such a message goes away with the busy state.
  bool _messageIsBusy = false;

  bool get isBusy => _isBusy;
  String? get statusMessage => _statusMessage;
  int? get rowCount => _rowCount;
  int? get columnCount => _columnCount;
  Duration? get lastQueryDuration => _lastQueryDuration;

  /// Marks the shell busy (spinner + optional message).
  void beginBusy({String? message}) {
    _isBusy = true;
    if (message != null) {
      _statusMessage = message;
      _messageIsBusy = true;
    }
    notifyListeners();
  }

  /// Clears busy; keeps last query metrics unless [clearMetrics] is true.
  ///
  /// A message set by [beginBusy] is dropped: it described work that is over.
  void endBusy({bool clearMetrics = false}) {
    _isBusy = false;
    if (_messageIsBusy) {
      _statusMessage = null;
      _messageIsBusy = false;
    }
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
    // The message describes this result. A plain row count passes none (the
    // counts are shown beside it), and then neither "Running query…" nor the
    // text of an earlier run may stay (#1556).
    _statusMessage = message;
    _messageIsBusy = false;
    notifyListeners();
  }

  /// Publishes a query (or command) that failed and clears busy. The row and
  /// column counts of an earlier result are dropped so they are not read as
  /// this run's.
  void reportQueryFailure({
    Duration? duration,
    String message = 'Query failed',
  }) {
    _isBusy = false;
    _statusMessage = message;
    _messageIsBusy = false;
    _rowCount = null;
    _columnCount = null;
    if (duration != null) _lastQueryDuration = duration;
    notifyListeners();
  }

  /// Replaces the shown message and query metrics, for example with those of
  /// the tab that has just been selected, or with a notice such as `Nothing to
  /// run`. Nulls clear the field. While a query is running the busy message
  /// owns the bar and this does nothing.
  void setQueryMetrics({
    String? message,
    int? rowCount,
    int? columnCount,
    Duration? duration,
  }) {
    if (_isBusy) return;
    _statusMessage = message;
    _messageIsBusy = false;
    _rowCount = rowCount;
    _columnCount = columnCount;
    _lastQueryDuration = duration;
    notifyListeners();
  }

  /// Clears busy + metrics (e.g. connection switch).
  void clear() {
    _isBusy = false;
    _statusMessage = null;
    _messageIsBusy = false;
    _rowCount = null;
    _columnCount = null;
    _lastQueryDuration = null;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() => clear();
}
