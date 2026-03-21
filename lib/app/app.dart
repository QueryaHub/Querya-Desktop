import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../features/main_screen/main_screen.dart';

class QueryaApp extends StatelessWidget {
  const QueryaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'Querya',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      // Less churn in ShadcnAnimatedTheme; helps stability with overlay layers.
      enableThemeAnimation: false,
      // Avoids scroll interception fighting nested Scrollbars in data views.
      enableScrollInterception: false,
      home: const MainScreen(),
    );
  }
}
