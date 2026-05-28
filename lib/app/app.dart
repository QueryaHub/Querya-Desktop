import 'package:querya_desktop/core/theme/querya_material_theme.dart';
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
        final colorScheme = queryaTheme.colorScheme;
        return ShadcnApp(
          title: 'Querya',
          theme: themeController.lightShadcnTheme,
          darkTheme: themeController.darkShadcnTheme,
          themeMode: themeController.themeMode,
          materialTheme: materialThemeFromQuerya(colorScheme),
          debugShowCheckedModeBanner: false,
          enableThemeAnimation: themeController.themeAnimationEnabled,
          enableScrollInterception: false,
          // Above navigator so dialogs/overlays (SQL editor, Preferences) see tokens.
          builder: (context, child) => QueryaThemeScope(
            data: queryaTheme,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AppLifecycleCleanup(
            child: MainScreen(),
          ),
        );
      },
    );
  }
}
