import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_color_scheme.dart';

/// App theme: dark only. Used for both theme and darkTheme so the app is always dark.
abstract class AppTheme {
  static ThemeData get dark => const ThemeData.dark(
        colorScheme: QueryaColorScheme.dark,
        radius: 0.58,
        scaling: 1,
        typography: Typography.geist(),
      );
}
