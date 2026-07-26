import 'dart:async';

/// Debounced + flush-on-dispose persistence for the connections sidebar width.
///
/// Keyboard/semantics resize has no drag-end; drag settle may outlive the
/// widget. Callers mark dirty and either debounce, wait for settle, or flush.
class ConnectionsPanelWidthPersist {
  ConnectionsPanelWidthPersist({
    required Future<void> Function(double width) write,
    this.discreteDebounce = const Duration(milliseconds: 300),
  }) : _write = write;

  final Future<void> Function(double width) _write;
  final Duration discreteDebounce;

  Timer? _discreteTimer;
  var dirty = false;

  void markDirty() => dirty = true;

  Future<void> persist(double width) async {
    await _write(width);
    dirty = false;
  }

  /// Keyboard / semantics step — no drag-end; debounce writes.
  ///
  /// [currentWidth] is read when the timer fires so rapid steps persist the
  /// latest value, not a stale snapshot from the first keypress.
  void onDiscreteResize(double Function() currentWidth) {
    markDirty();
    _discreteTimer?.cancel();
    _discreteTimer = Timer(discreteDebounce, () {
      unawaited(persist(currentWidth()));
    });
  }

  void cancelDiscreteTimer() => _discreteTimer?.cancel();

  /// Cancel timers and flush if a resize was not yet written.
  void disposeFlush(double width) {
    _discreteTimer?.cancel();
    _discreteTimer = null;
    if (dirty) {
      unawaited(_write(width));
      dirty = false;
    }
  }
}
