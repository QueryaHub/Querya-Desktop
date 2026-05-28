import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_theme.dart';

/// Shadcn [ColorScheme] presets — derived from [QueryaTheme] defaults.
abstract class QueryaColorScheme {
  static ColorScheme get dark => QueryaTheme.darkDefault.colorScheme;
  static ColorScheme get light => QueryaTheme.lightDefault.colorScheme;
}
