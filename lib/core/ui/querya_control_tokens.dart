import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';

/// The raw numbers of the control scale (#1333). Constants so other token
/// classes can build `const` values from them; widgets read them through
/// [QueryaControlSize].
abstract final class QueryaControlMetrics {
  static const double heightSm = 28;
  static const double heightMd = 32;
  static const double heightLg = 36;

  static const double fontSm = 12;
  static const double fontMd = 13;
  static const double fontLg = 14;

  static const double iconSm = 15;
  static const double iconMd = 16;
  static const double iconLg = 18;

  /// One corner radius for buttons, icon buttons, dropdown triggers, search
  /// fields and tab pills.
  static const double radius = 6;
}

/// One of the three control sizes of the Querya UI kit. Buttons, icon buttons,
/// dropdown triggers, search fields and tab strips of one size share a height,
/// so a toolbar row built from them has one height (docs/ui-kit.md).
///
/// Values are logical px at `uiScale` 1; the `scaled*` helpers apply the
/// app-wide UI scale.
enum QueryaControlSize {
  /// Tree headers, grid and panel toolbars, dense rows.
  sm(
    height: QueryaControlMetrics.heightSm,
    horizontalPadding: 8,
    fontSize: QueryaControlMetrics.fontSm,
    iconSize: QueryaControlMetrics.iconSm,
    iconGap: 6,
  ),

  /// Top toolbars, editor toolbars, ERD, result bars.
  md(
    height: QueryaControlMetrics.heightMd,
    horizontalPadding: 12,
    fontSize: QueryaControlMetrics.fontMd,
    iconSize: QueryaControlMetrics.iconMd,
    iconGap: 6,
  ),

  /// Dialog footers, forms, empty-state actions.
  lg(
    height: QueryaControlMetrics.heightLg,
    horizontalPadding: 16,
    fontSize: QueryaControlMetrics.fontLg,
    iconSize: QueryaControlMetrics.iconLg,
    iconGap: 8,
  );

  const QueryaControlSize({
    required this.height,
    required this.horizontalPadding,
    required this.fontSize,
    required this.iconSize,
    required this.iconGap,
  });

  final double height;
  final double horizontalPadding;
  final double fontSize;
  final double iconSize;
  final double iconGap;

  /// Corner radius; the same for every size.
  double get radius => QueryaControlMetrics.radius;

  double scaledHeight(BuildContext context) => context.scaled(height);

  double scaledHorizontalPadding(BuildContext context) =>
      context.scaled(horizontalPadding);

  double scaledFontSize(BuildContext context) => context.scaled(fontSize);

  double scaledIconSize(BuildContext context) => context.scaled(iconSize);

  double scaledIconGap(BuildContext context) => context.scaled(iconGap);

  double scaledRadius(BuildContext context) => context.scaled(radius);

  /// The size a control without an explicit one uses here: the nearest
  /// [QueryaControlScope], or [md].
  static QueryaControlSize of(BuildContext context) =>
      QueryaControlScope.maybeOf(context) ?? QueryaControlSize.md;
}

/// Sets the default [QueryaControlSize] of a subtree: a toolbar says its size
/// once and the controls in it follow. A control's own `size` still wins.
class QueryaControlScope extends InheritedWidget {
  const QueryaControlScope({
    super.key,
    required this.size,
    required super.child,
  });

  final QueryaControlSize size;

  /// The size set by the nearest scope, or null when there is none.
  static QueryaControlSize? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<QueryaControlScope>()
      ?.size;

  @override
  bool updateShouldNotify(QueryaControlScope oldWidget) =>
      size != oldWidget.size;
}
