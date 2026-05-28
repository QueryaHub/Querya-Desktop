import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'app_lifecycle_cleanup.dart';
import '../features/main_screen/main_screen.dart';

class QueryaApp extends StatelessWidget {
  const QueryaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.instance;

    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final queryaTheme = themeController.activeTheme;
        return ShadcnApp(
          title: 'Querya',
          theme: themeController.lightShadcnTheme,
          darkTheme: themeController.darkShadcnTheme,
          themeMode: themeController.themeMode,
          debugShowCheckedModeBanner: false,
          enableThemeAnimation: false,
          enableScrollInterception: false,
          home: QueryaThemeScope(
            data: queryaTheme,
            child: const AppLifecycleCleanup(
              child: MainScreen(),
            ),
          ),
        );
      },
    );
  }
}
