import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'querya_spring.dart';

/// Drives a scalar with interruptible / redirectable spring motion.
///
/// Call [animateTo] to retarget; the current presentation value and velocity
/// are preserved (no brick-wall).
///
/// When [useSprings] is false:
/// - if [cubicDuration] is non-null and non-zero → duration-token cubic (#493)
/// - otherwise → snap via [jumpTo] (Off / drag settle)
class QueryaSpringController extends ChangeNotifier {
  QueryaSpringController({
    required TickerProvider vsync,
    double value = 0,
    this.spring = QueryaSpring.snappy,
    this.useSprings = true,
    this.cubicDuration,
    this.cubicCurve = Curves.easeOutCubic,
  }) : _value = value,
       _target = value {
    _ticker = vsync.createTicker(_onTick);
  }

  SpringDescription spring;
  bool useSprings;

  /// Cubic fallback when springs are off (Reduced motion). Null / zero → snap.
  Duration? cubicDuration;
  Curve cubicCurve;

  late final Ticker _ticker;
  double _value;
  double _velocity = 0;
  double _target;
  SpringSimulation? _simulation;
  Duration? _simulationStart;

  double? _cubicFrom;
  Duration? _cubicTotal;
  Curve? _cubicActiveCurve;

  double get value => _value;
  double get velocity => _velocity;
  double get target => _target;
  bool get isAnimating => _ticker.isActive;

  /// Instantly sets value (and clears velocity).
  void jumpTo(double value) {
    _ticker.stop();
    _clearMotion();
    _velocity = 0;
    _target = value;
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }

  /// Animates toward [target], inheriting current velocity when redirecting.
  void animateTo(double target, {double? velocity}) {
    _target = target;
    final startVelocity = velocity ?? _velocity;

    if (!useSprings) {
      final duration = cubicDuration;
      if (duration == null || duration == Duration.zero) {
        jumpTo(target);
        return;
      }
      _startCubic(target, duration);
      return;
    }

    if ((_value - target).abs() < 0.0001 && startVelocity.abs() < 0.0001) {
      jumpTo(target);
      return;
    }

    _cubicFrom = null;
    _cubicTotal = null;
    _cubicActiveCurve = null;
    _simulation = QueryaSpring.simulation(
      description: spring,
      start: _value,
      end: target,
      velocity: startVelocity,
    );
    _simulationStart = null;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _startCubic(double target, Duration duration) {
    if ((_value - target).abs() < 0.0001) {
      jumpTo(target);
      return;
    }
    _simulation = null;
    _cubicFrom = _value;
    _cubicTotal = duration;
    _cubicActiveCurve = cubicCurve;
    _velocity = 0;
    _simulationStart = null;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _clearMotion() {
    _simulation = null;
    _simulationStart = null;
    _cubicFrom = null;
    _cubicTotal = null;
    _cubicActiveCurve = null;
  }

  void _onTick(Duration elapsed) {
    final cubicTotal = _cubicTotal;
    if (cubicTotal != null) {
      _onCubicTick(elapsed, cubicTotal);
      return;
    }

    final simulation = _simulation;
    if (simulation == null) {
      _ticker.stop();
      return;
    }

    _simulationStart ??= elapsed;
    final t = (elapsed - _simulationStart!).inMicroseconds / 1e6;
    final next = simulation.x(t);
    _velocity = simulation.dx(t);
    final settled = simulation.isDone(t) ||
        ((next - _target).abs() < 0.15 && _velocity.abs() < 1.0);

    if (settled) {
      _value = _target;
      _velocity = 0;
      _clearMotion();
      _ticker.stop();
      notifyListeners();
      return;
    }

    _value = next;
    notifyListeners();
  }

  void _onCubicTick(Duration elapsed, Duration cubicTotal) {
    _simulationStart ??= elapsed;
    final micros = cubicTotal.inMicroseconds;
    if (micros <= 0) {
      jumpTo(_target);
      return;
    }
    final t =
        (elapsed - _simulationStart!).inMicroseconds / micros;
    final from = _cubicFrom ?? _value;
    final curve = _cubicActiveCurve ?? cubicCurve;

    if (t >= 1) {
      _value = _target;
      _velocity = 0;
      _clearMotion();
      _ticker.stop();
      notifyListeners();
      return;
    }

    final curved = curve.transform(t.clamp(0.0, 1.0));
    _value = from + (_target - from) * curved;
    _velocity = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
