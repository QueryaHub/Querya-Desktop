import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/theme/querya_material_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// The default dark theme as the app hands it to [material.MaterialApp].
material.ThemeData get queryaDarkMaterialTheme =>
    materialThemeFromQuerya(QueryaTheme.darkDefault.colors);

/// Wraps [child] with [material.MaterialApp] and [QueryaThemeScope] for widget
/// tests.
Widget queryaThemeTestShell({
  required Widget child,
  QueryaTheme data = QueryaTheme.darkDefault,
  material.ThemeData? theme,
  double uiScale = 1.0,
}) {
  final td = theme ?? materialThemeFromQuerya(data.colors);
  return material.MaterialApp(
    theme: td,
    darkTheme: td,
    themeMode: material.ThemeMode.dark,
    builder: (context, appChild) => QueryaUiScaleScope(
      scale: uiScale,
      child: QueryaThemeScope(
        data: data,
        child: appChild ?? const SizedBox.shrink(),
      ),
    ),
    // ShadcnApp gave the page a surface; a bare MaterialApp page has none, and
    // the kit's text fields need a Material ancestor.
    home: material.Material(
        type: material.MaterialType.transparency, child: child),
  );
}
