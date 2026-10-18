import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';

import 'querya_editor_theme.dart';
import 'querya_semantic_palette.dart';
import 'querya_theme.dart';
import 'querya_ui_colors.dart';
import 'querya_workbench_theme.dart';

/// Provides [QueryaTheme] (workbench, editor and colour tokens) below the app.
class QueryaThemeScope extends InheritedWidget {
  const QueryaThemeScope({
    super.key,
    required this.data,
    required super.child,
    this.transitioning = false,
  });

  final QueryaTheme data;

  /// Whether [data] is an intermediate frame of a theme animation. Consumers
  /// that are costly to update (syntax highlighters) can wait for the final
  /// frame instead of following every interpolated colour (#1358).
  final bool transitioning;

  static QueryaTheme of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<QueryaThemeScope>();
    assert(scope != null, 'QueryaThemeScope not found in context');
    return scope!.data;
  }

  static QueryaTheme? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<QueryaThemeScope>()?.data;
  }

  /// Whether the theme is mid-animation. Registers a dependency, so the caller
  /// is rebuilt when the animation ends.
  static bool isTransitioning(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<QueryaThemeScope>()
            ?.transitioning ??
        false;
  }

  @override
  bool updateShouldNotify(QueryaThemeScope oldWidget) =>
      data != oldWidget.data || transitioning != oldWidget.transitioning;
}

/// Convenient access to [QueryaTheme] tokens and [Theme] / [ColorScheme] from [BuildContext].
extension QueryaThemeContext on BuildContext {
  /// Shortcut for Material [material.Theme.of].
  material.ThemeData get theme => material.Theme.of(this);

  /// The colours widgets read (#1730): the nearest [QueryaThemeScope]'s, which
  /// follows a theme animation frame by frame. Without a scope (a bare app in a
  /// test) the default theme of the ambient brightness.
  QueryaUiColors get colors =>
      (QueryaThemeScope.maybeOf(this) ?? _defaultTheme).colors;

  QueryaTheme get _defaultTheme => _ambientBrightness == Brightness.light
      ? QueryaTheme.lightDefault
      : QueryaTheme.darkDefault;

  QueryaTheme get queryaTheme => QueryaThemeScope.of(this);

  /// The brightness the defaults below follow when there is no
  /// [QueryaThemeScope]: Material's (a widget under a bare app, as in tests).
  Brightness get _ambientBrightness => material.Theme.of(this).brightness;

  QueryaWorkbenchTheme get workbench => workbenchOrDefault;

  /// The workbench tokens of the nearest [QueryaThemeScope], or the defaults
  /// for the ambient brightness when there is none (a widget under a bare app,
  /// as in tests). Kit controls use this so they never assert on a missing
  /// scope.
  QueryaWorkbenchTheme get workbenchOrDefault =>
      QueryaThemeScope.maybeOf(this)?.workbench ??
      (_ambientBrightness == Brightness.light
          ? QueryaWorkbenchTheme.lightDefault
          : QueryaWorkbenchTheme.darkDefault);

  QueryaEditorTheme get editorTheme =>
      QueryaThemeScope.maybeOf(this)?.editor ??
      (_ambientBrightness == Brightness.light
          ? QueryaEditorTheme.lightDefault
          : QueryaEditorTheme.darkDefault);

  QueryaSemanticPalette get semanticPalette =>
      QueryaSemanticPalette.fromTheme(
        QueryaThemeScope.maybeOf(this) ??
            (_ambientBrightness == Brightness.light
                ? QueryaTheme.lightDefault
                : QueryaTheme.darkDefault),
      );
}
