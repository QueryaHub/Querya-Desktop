import 'package:shadcn_flutter/shadcn_flutter.dart';

/// App theme: dark only. Used for both theme and darkTheme so the app is always dark.
abstract class AppTheme {
  static ThemeData get dark => ThemeData.dark(
        colorScheme: ColorSchemes.darkSlate,
        radius: 0.5,
        scaling: 1,
        typography: const Typography.geist(),
      );
}
