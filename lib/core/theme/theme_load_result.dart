import 'querya_theme.dart';
import 'theme_definition.dart';

/// Result of loading a [ThemeDefinition] into a runtime [QueryaTheme].
sealed class ThemeLoadResult {
  const ThemeLoadResult();
}

class ThemeLoadSuccess extends ThemeLoadResult {
  const ThemeLoadSuccess({
    required this.definition,
    required this.theme,
  });

  final ThemeDefinition definition;
  final QueryaTheme theme;
}

class ThemeLoadFailure extends ThemeLoadResult {
  const ThemeLoadFailure({
    required this.definition,
    required this.message,
    this.error,
  });

  final ThemeDefinition definition;
  final String message;
  final Object? error;
}
