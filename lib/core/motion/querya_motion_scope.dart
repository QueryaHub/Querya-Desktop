import 'package:flutter/material.dart';

/// In-app motion intensity. Wired to Preferences in UI-A5 (#175); defaults to
/// [full] until then.
enum QueryaMotionLevel {
  full,
  reduced,
  off,
}

/// Provides [QueryaMotionLevel] for [QueryaMotion.effectiveDuration].
///
/// Place near the app root when the Preferences toggle lands; optional until
/// then — missing scope means [QueryaMotionLevel.full].
class QueryaMotionScope extends InheritedWidget {
  const QueryaMotionScope({
    super.key,
    required this.level,
    required super.child,
  });

  final QueryaMotionLevel level;

  static QueryaMotionLevel? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<QueryaMotionScope>()
        ?.level;
  }

  static QueryaMotionLevel of(BuildContext context) {
    return maybeOf(context) ?? QueryaMotionLevel.full;
  }

  @override
  bool updateShouldNotify(QueryaMotionScope oldWidget) =>
      level != oldWidget.level;
}
