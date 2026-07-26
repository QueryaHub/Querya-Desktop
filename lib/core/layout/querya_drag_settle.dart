import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:querya_desktop/core/motion/querya_spring_controller.dart';

/// Direct mid-drag tracking with optional spring settle on release.
///
/// While dragging, [dragTo] jumps 1:1 (no lag). On [settle], a spring inherits
/// release [velocity] toward the current value so the pane soft-stops /
/// overshoots briefly — never applied mid-drag.
class QueryaDragSettleController extends ChangeNotifier {
  QueryaDragSettleController({
    required TickerProvider vsync,
    required double value,
    this.spring = QueryaSpring.gentle,
    this.maxSettleVelocity = 2.5,
  }) : _value = value {
    _spring = QueryaSpringController(
      vsync: vsync,
      value: value,
      spring: spring,
    );
    _spring.addListener(_onSpringTick);
  }

  final SpringDescription spring;

  /// Cap on |velocity| passed into the settle spring (value-units / second).
  final double maxSettleVelocity;

  late final QueryaSpringController _spring;
  double _value;
  var _dragging = false;

  double get value => _value;
  bool get isSettling => !_dragging && _spring.isAnimating;

  /// Instant set (restore from settings, clamp after layout).
  void jumpTo(double value) {
    _dragging = false;
    _spring.jumpTo(value);
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }

  /// Mid-drag update — cancels settle and tracks exactly.
  void dragTo(double value) {
    _dragging = true;
    if (_spring.isAnimating) {
      _spring.jumpTo(value);
    } else {
      _spring.jumpTo(value);
    }
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }

  /// Drag-end settle using release velocity (same units as [value] / second).
  void settle({
    required double velocity,
    required bool useSprings,
  }) {
    _dragging = false;
    _spring.useSprings = useSprings;
    final v = velocity.clamp(-maxSettleVelocity, maxSettleVelocity);
    if (!useSprings || v.abs() < 0.02) {
      _spring.jumpTo(_value);
      return;
    }
    _spring.jumpTo(_value);
    _spring.animateTo(_value, velocity: v);
  }

  void _onSpringTick() {
    if (_dragging) return;
    final next = _spring.value;
    if ((next - _value).abs() < 0.0001) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _spring.removeListener(_onSpringTick);
    _spring.dispose();
    super.dispose();
  }
}
