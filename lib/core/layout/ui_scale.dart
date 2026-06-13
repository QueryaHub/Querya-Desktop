import 'package:flutter/widgets.dart';

/// App-wide UI scale factor (Preferences → Appearance).
class QueryaUiScaleScope extends InheritedWidget {
  const QueryaUiScaleScope({
    super.key,
    required this.scale,
    required super.child,
  });

  final double scale;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<QueryaUiScaleScope>()
            ?.scale ??
        1.0;
  }

  @override
  bool updateShouldNotify(QueryaUiScaleScope oldWidget) =>
      oldWidget.scale != scale;
}

extension QueryaUiScaleContext on BuildContext {
  double get uiScale => QueryaUiScaleScope.of(this);

  double scaled(double logicalPixels) => logicalPixels * uiScale;
}
