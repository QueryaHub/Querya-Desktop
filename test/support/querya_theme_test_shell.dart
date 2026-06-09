import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Wraps [child] with [ShadcnApp] and [QueryaThemeScope] for widget tests.
Widget queryaThemeTestShell({
  required Widget child,
  QueryaTheme data = QueryaTheme.darkDefault,
  ThemeData? theme,
}) {
  final td = theme ?? data.toShadcnThemeData();
  return ShadcnApp(
    theme: td,
    darkTheme: td,
    themeMode: ThemeMode.dark,
    builder: (context, appChild) => QueryaUiScaleScope(
      scale: 1.0,
      child: QueryaThemeScope(
        data: data,
        child: appChild ?? const SizedBox.shrink(),
      ),
    ),
    home: child,
  );
}
