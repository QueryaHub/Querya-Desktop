import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../models/display_info.dart';
import '../models/enums.dart';
import '../models/session_report.dart';
import 'fps_tracker.dart';
import 'session_scorer.dart';

/// An active FPS benchmark session that records frame timings.
///
/// Create via [RefreshRate.startSession] and call [end] to receive a
/// [SessionReport] with verdict, FPS stats, and bottleneck analysis.
///
/// The session automatically pauses when the app goes to the background and
/// resumes (with a warm-up exclusion window) when the app returns to the
/// foreground.
class RefreshRateSession {
  /// The human-readable name given to this session.
  final String name;
  SessionState _state;
  final DateTime _startedAt;
  final double _targetHz;
  final DisplayInfo _initialInfo;
  final FpsTracker _tracker = FpsTracker();
  Duration _excludedDuration = Duration.zero;
  final Map<ExclusionReason, int> _exclusions = {};
  TimingsCallback? _timingsCallback;
  AppLifecycleListener? _lifecycleListener;
  DateTime? _inactiveAt;
  static const _warmupDuration = Duration(milliseconds: 500);

  RefreshRateSession._({
    required this.name,
    required SessionState state,
    required DateTime startedAt,
    required double targetHz,
    required DisplayInfo initialInfo,
  })  : _state = state,
        _startedAt = startedAt,
        _targetHz = targetHz,
        _initialInfo = initialInfo;

  /// Creates and starts a new tracking session.
  static RefreshRateSession create(String name, DisplayInfo info) {
    final session = RefreshRateSession._(
      name: name,
      state: SessionState.running,
      startedAt: DateTime.now(),
      targetHz: info.maxRate,
      initialInfo: info,
    );
    session._timingsCallback = session._tracker.addTimings;
    SchedulerBinding.instance.addTimingsCallback(session._timingsCallback!);
    session._registerLifecycleObserver();
    return session;
  }

  /// Current lifecycle state of the session.
  SessionState get state => _state;

  /// The time at which this session was created.
  DateTime get startedAt => _startedAt;

  /// The target refresh rate in Hz (taken from [DisplayInfo.maxRate] at creation time).
  double get targetHz => _targetHz;

  /// Stops frame timing collection and computes a [SessionReport].
  ///
  /// Must be called exactly once. After this call the session is in
  /// [SessionState.completed] and further calls have undefined behaviour.
  Future<SessionReport> end() async {
    _stopTracking();
    _state = SessionState.completed;
    return SessionScorer.compute(
      sessionName: name,
      tracker: _tracker,
      targetHz: _targetHz,
      validDuration: DateTime.now().difference(_startedAt) - _excludedDuration,
      excludedDuration: _excludedDuration,
      exclusionReasons: Map.unmodifiable(_exclusions),
      deviceState: DeviceStateSnapshot(
        isLowPowerMode: _initialInfo.isLowPowerMode,
        thermalState: _initialInfo.thermalState,
        hasAdaptiveRefreshRate: _initialInfo.hasAdaptiveRefreshRate,
        displayServer: _initialInfo.displayServer,
        monitorCount: _initialInfo.monitorCount,
      ),
    );
  }

  void _registerLifecycleObserver() {
    _lifecycleListener = AppLifecycleListener(
      onHide: _onInactive,
      onInactive: _onInactive,
      onPause: _onInactive,
      onResume: _onResume,
    );
  }

  void _onInactive() {
    if (_state != SessionState.running) return;
    _state = SessionState.interrupted;
    _inactiveAt = DateTime.now();
    _addExclusion(ExclusionReason.appBackgrounded);
  }

  void _onResume() {
    if (_state != SessionState.interrupted) return;
    if (_inactiveAt != null) {
      _excludedDuration += DateTime.now().difference(_inactiveAt!);
      _inactiveAt = null;
    }
    _state = SessionState.warmup;
    Future.delayed(_warmupDuration, () {
      if (_state == SessionState.warmup) {
        _excludedDuration += _warmupDuration;
        _addExclusion(ExclusionReason.resumeWarmup);
        _state = SessionState.running;
      }
    });
  }

  void _addExclusion(ExclusionReason reason) {
    _exclusions[reason] = (_exclusions[reason] ?? 0) + 1;
  }

  void _stopTracking() {
    if (_timingsCallback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
      _timingsCallback = null;
    }
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }
}
