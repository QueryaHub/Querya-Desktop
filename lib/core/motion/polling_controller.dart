import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What the last polls did: when one last succeeded and how many failed since.
@immutable
class PollStatus {
  const PollStatus({this.lastSuccess, this.lastError, this.failures = 0});

  final DateTime? lastSuccess;
  final Object? lastError;

  /// Consecutive failed ticks; zero after a success.
  final int failures;

  /// The latest tick failed, so what the view shows is older than it looks.
  bool get isStale => failures > 0;
}

/// Polls with [tick] every [interval], one request at a time.
///
/// The next tick is scheduled when the previous one has finished, so a slow
/// server is never asked again while it is still answering, and results land
/// in the order they were asked for. A failed tick backs the interval off
/// exponentially (up to [maxBackoff]) and is reported through [status]; the
/// first success returns to [interval].
///
/// Start and stop with [setActive], from `didChangeDependencies` (reading
/// `TickerMode`) and from the places that change whether the view has data,
/// not from `build`.
class PollingController {
  PollingController({
    required Duration interval,
    required this.tick,
    this.maxBackoff = const Duration(minutes: 1),
  }) : _interval = interval;

  /// One poll. Throw to report a failure.
  final Future<void> Function() tick;
  final Duration maxBackoff;

  final ValueNotifier<PollStatus> status =
      ValueNotifier<PollStatus>(const PollStatus());

  Duration _interval;
  Timer? _timer;
  bool _active = false;
  bool _inFlight = false;
  bool _disposed = false;

  /// Bumped on every stop, so a tick that was running when polling stopped
  /// does not schedule the next one or report into the new session.
  int _epoch = 0;

  Duration get interval => _interval;
  bool get isActive => _active;

  /// The wait before the next tick: [interval], doubled for each failure.
  Duration get nextDelay {
    final failures = status.value.failures;
    if (failures == 0 || _interval >= maxBackoff) return _interval;
    final micros = _interval.inMicroseconds * (1 << math.min(failures, 16));
    return Duration(microseconds: math.min(micros, maxBackoff.inMicroseconds));
  }

  void setActive(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _epoch++;
    if (active) {
      _schedule();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void setInterval(Duration interval) {
    if (interval == _interval) return;
    _interval = interval;
    if (_active && !_inFlight) _schedule();
  }

  /// Forgets what the previous session reported (a reconnect, a retry).
  void reset() {
    if (_disposed) return;
    status.value = const PollStatus();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(nextDelay, _run);
  }

  Future<void> _run() async {
    _timer = null;
    if (_disposed || !_active) return;
    if (_inFlight) {
      // A tick from before a stop/start is still answering.
      _schedule();
      return;
    }
    final epoch = _epoch;
    _inFlight = true;
    try {
      await tick();
      if (_disposed || epoch != _epoch) return;
      status.value = PollStatus(lastSuccess: DateTime.now());
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      final previous = status.value;
      status.value = PollStatus(
        lastSuccess: previous.lastSuccess,
        lastError: e,
        failures: previous.failures + 1,
      );
    } finally {
      _inFlight = false;
    }
    if (!_disposed && _active && epoch == _epoch) _schedule();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    status.dispose();
  }
}

/// Wires a [PollingController] to a [State]: polls while the view is under an
/// enabled `TickerMode` (not an offscreen keep-alive layer), has data to
/// refresh ([pollShouldRun]) and has an interval ([pollInterval], null = off).
///
/// Call [syncPolling] whenever the answer to [pollShouldRun] or [pollInterval]
/// may have changed (a load finished or failed, the interval was picked) and
/// [stopPolling] when the data is dropped (a reload, another connection).
mixin PollingState<T extends StatefulWidget> on State<T> {
  Duration? get pollInterval;
  bool get pollShouldRun;

  /// One poll; throw to report a failure to [PollingController.status].
  Future<void> pollTick();

  late final PollingController polling = PollingController(
    interval: pollInterval ?? const Duration(seconds: 5),
    tick: pollTick,
  );

  bool _tickerEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    syncPolling();
  }

  void syncPolling() {
    final interval = pollInterval;
    if (interval != null) polling.setInterval(interval);
    polling.setActive(
      mounted && _tickerEnabled && interval != null && pollShouldRun,
    );
  }

  void stopPolling() {
    polling
      ..setActive(false)
      ..reset();
  }

  @override
  void dispose() {
    polling.dispose();
    super.dispose();
  }
}
