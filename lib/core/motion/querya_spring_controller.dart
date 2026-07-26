import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'querya_spring.dart';

/// Drives a scalar with interruptible / redirectable spring motion.
///
/// Call [animateTo] to retarget; the current presentation value and velocity
/// are preserved (no brick-wall). When [useSprings] is false, snaps via
/// [jumpTo].
class QueryaSpringController extends ChangeNotifier {
  QueryaSpringController({
    required TickerProvider vsync,
    double value = 0,
    this.spring = QueryaSpring.snappy,
    this.useSprings = true,
  }) : _value = value,
       _target = value {
    _ticker = vsync.createTicker(_onTick);
  }

  SpringDescription spring;
  bool useSprings;

  late final Ticker _ticker;
  double _value;
  double _velocity = 0;
  double _target;
  SpringSimulation? _simulation;
  Duration? _simulationStart;

  double get value => _value;
  double get velocity => _velocity;
  double get target => _target;
  bool get isAnimating => _ticker.isActive;

  /// Instantly sets value (and clears velocity).
  void jumpTo(double value) {
    _ticker.stop();
    _simulation = null;
    _simulationStart = null;
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
      jumpTo(target);
      return;
    }

    if ((_value - target).abs() < 0.0001 && startVelocity.abs() < 0.0001) {
      jumpTo(target);
      return;
    }

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

  void _onTick(Duration elapsed) {
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
        ((next - _target).abs() < 0.0005 && _velocity.abs() < 0.01);

    if (settled) {
      _value = _target;
      _velocity = 0;
      _simulation = null;
      _simulationStart = null;
      _ticker.stop();
      notifyListeners();
      return;
    }

    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
