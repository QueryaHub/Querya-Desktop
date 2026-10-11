import 'package:shadcn_flutter/shadcn_flutter.dart' hide TextExtension;

import 'querya_theme.dart';

/// App theme presets built from [QueryaTheme].
abstract class AppTheme {
  static ThemeData get dark => QueryaTheme.darkDefault.toShadcnThemeData();

  static ThemeData get light => QueryaTheme.lightDefault.toShadcnThemeData();
}
