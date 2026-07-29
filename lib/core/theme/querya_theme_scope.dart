import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import 'querya_editor_theme.dart';
import 'querya_semantic_palette.dart';
import 'querya_theme.dart';
import 'querya_workbench_theme.dart';

/// Provides [QueryaTheme] (workbench + editor tokens) below [ShadcnApp].
class QueryaThemeScope extends InheritedWidget {
  const QueryaThemeScope({
    super.key,
    required this.data,
    required super.child,
  });

  final QueryaTheme data;

  static QueryaTheme of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<QueryaThemeScope>();
    assert(scope != null, 'QueryaThemeScope not found in context');
    return scope!.data;
  }

  static QueryaTheme? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<QueryaThemeScope>()?.data;
  }

  @override
  bool updateShouldNotify(QueryaThemeScope oldWidget) => data != oldWidget.data;
}

/// Convenient access to [QueryaTheme] tokens and [Theme] / [ColorScheme] from [BuildContext].
extension QueryaThemeContext on BuildContext {
  /// Shortcut for Material [material.Theme.of].
  material.ThemeData get theme => material.Theme.of(this);

  /// Shortcut for [shadcn.ColorScheme] from [shadcn.Theme.of].
  shadcn.ColorScheme get colors => shadcn.Theme.of(this).colorScheme;

  QueryaTheme get queryaTheme => QueryaThemeScope.of(this);

  QueryaWorkbenchTheme get workbench => queryaTheme.workbench;

  QueryaEditorTheme get editorTheme => queryaTheme.editor;

  QueryaSemanticPalette get semanticPalette =>
      QueryaSemanticPalette.fromTheme(queryaTheme);
}
