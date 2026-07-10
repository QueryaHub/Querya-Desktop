/// Exponential backoff for sandboxed plugin restarts (Block E §4).
///
/// Up to [maxAttempts] retries inside [window], with delays 1s → 2s → 4s.
///
/// Usage after a crash:
/// ```dart
/// final delay = recovery.recordFailure();
/// if (delay == null) { /* give up */ }
/// else { await Future.delayed(delay); /* respawn */ }
/// ```
class SandboxAutoRecovery {
  SandboxAutoRecovery({
    this.maxAttempts = 3,
    this.window = const Duration(minutes: 5),
    this.backoffSchedule = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration window;
  final List<Duration> backoffSchedule;
  final DateTime Function() _clock;

  final List<DateTime> _failures = [];

  /// Failures still counted inside the current [window].
  int get recentFailureCount {
    _prune();
    return _failures.length;
  }

  /// Whether another retry is allowed (call before or after checking
  /// [recordFailure]'s return value).
  bool get canRetry {
    _prune();
    return _failures.length < maxAttempts;
  }

  /// Suggested delay before the next spawn given current failure count.
  /// Returns `null` when retries are exhausted.
  Duration? nextBackoff() {
    _prune();
    if (_failures.length >= maxAttempts) return null;
    final index = _failures.length.clamp(0, backoffSchedule.length - 1);
    return backoffSchedule[index];
  }

  /// Records a crash / deadlock.
  ///
  /// Returns the backoff before the next retry, or `null` if the caller must
  /// stop retrying (more than [maxAttempts] failures in [window]).
  Duration? recordFailure() {
    _failures.add(_clock());
    _prune();
    if (_failures.length > maxAttempts) {
      return null;
    }
    final index = (_failures.length - 1).clamp(0, backoffSchedule.length - 1);
    return backoffSchedule[index];
  }

  void recordSuccess() => _failures.clear();

  void reset() => _failures.clear();

  void _prune() {
    final cutoff = _clock().subtract(window);
    _failures.removeWhere((t) => t.isBefore(cutoff));
  }
}
