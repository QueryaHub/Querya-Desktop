import 'package:flutter/material.dart';

import 'querya_theme.dart';
import 'querya_theme_scope.dart';

/// Cross-fades [QueryaTheme] tokens (workbench / editor / scheme) over [duration].
///
/// When [duration] is [Duration.zero], jumps immediately (motion Off / preference).
class AnimatedQueryaTheme extends ImplicitlyAnimatedWidget {
  const AnimatedQueryaTheme({
    super.key,
    required this.data,
    required super.duration,
    super.curve,
    required this.child,
  });

  final QueryaTheme data;
  final Widget child;

  @override
  AnimatedWidgetBaseState<AnimatedQueryaTheme> createState() =>
      _AnimatedQueryaThemeState();
}

class _AnimatedQueryaThemeState
    extends AnimatedWidgetBaseState<AnimatedQueryaTheme> {
  QueryaThemeTween? _data;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _data = visitor(
      _data,
      widget.data,
      (dynamic value) => QueryaThemeTween(begin: value as QueryaTheme),
    ) as QueryaThemeTween?;
  }

  @override
  Widget build(BuildContext context) {
    return QueryaThemeScope(
      data: _data!.evaluate(animation),
      child: widget.child,
    );
  }
}

/// Tween that lerps [QueryaTheme] via [QueryaTheme.lerp].
class QueryaThemeTween extends Tween<QueryaTheme> {
  QueryaThemeTween({super.begin, super.end});

  @override
  QueryaTheme lerp(double t) => QueryaTheme.lerp(begin!, end!, t);
}
