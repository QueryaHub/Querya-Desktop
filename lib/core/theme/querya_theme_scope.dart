import 'package:flutter/widgets.dart';

import 'querya_editor_theme.dart';
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

/// Convenient access to [QueryaTheme] tokens from [BuildContext].
extension QueryaThemeContext on BuildContext {
  QueryaTheme get queryaTheme => QueryaThemeScope.of(this);

  QueryaWorkbenchTheme get workbench => queryaTheme.workbench;

  QueryaEditorTheme get editorTheme => queryaTheme.editor;
}
