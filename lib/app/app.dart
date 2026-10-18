import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/core/motion/querya_motion_controller.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/motion/querya_theme_motion.dart';
import 'package:querya_desktop/core/theme/animated_querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';

import 'app_lifecycle_cleanup.dart';
import '../features/main_screen/main_screen.dart';

class QueryaApp extends StatelessWidget {
  const QueryaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.instance;
    final uiScaleController = UiScaleController.instance;
    final motionController = QueryaMotionController.instance;

    return ListenableBuilder(
      listenable: themeController,
      builder: (context, __) {
        final queryaTheme = themeController.activeTheme;

        return ListenableBuilder(
          listenable: uiScaleController,
          builder: (context, __) {
            final scale = uiScaleController.scale;
            return ListenableBuilder(
              listenable: motionController,
              builder: (context, __) {
                final motionLevel = motionController.level;
                final disableAnimations =
                    MediaQuery.maybeOf(context)?.disableAnimations ??
                        WidgetsBinding.instance.platformDispatcher
                            .accessibilityFeatures.disableAnimations;
                final themeDuration = QueryaThemeMotion.duration(
                  preferenceEnabled: themeController.themeAnimationEnabled,
                  level: motionLevel,
                  disableAnimations: disableAnimations,
                );
                final themeCurve = QueryaThemeMotion.curve(
                  preferenceEnabled: themeController.themeAnimationEnabled,
                  level: motionLevel,
                  disableAnimations: disableAnimations,
                );
                final themeAnimEnabled = QueryaThemeMotion.enabled(
                  preferenceEnabled: themeController.themeAnimationEnabled,
                  level: motionLevel,
                  disableAnimations: disableAnimations,
                );

                return MaterialApp(
                  title: 'Querya',
                  theme: themeController.lightMaterialTheme,
                  darkTheme: themeController.darkMaterialTheme,
                  themeMode: themeController.themeMode,
                  debugShowCheckedModeBanner: false,
                  // The Material theme follows the mode with the same
                  // duration as the Querya tokens below.
                  themeAnimationDuration:
                      themeAnimEnabled ? themeDuration : Duration.zero,
                  themeAnimationCurve: themeCurve,
                  // Above navigator so dialogs/overlays (SQL editor, Preferences) see tokens.
                  builder: (context, child) {
                    final mq = MediaQuery.maybeOf(context);
                    return QueryaUiScaleScope(
                      scale: scale,
                      child: MediaQuery(
                        data: (mq ?? const MediaQueryData()).copyWith(
                          textScaler: TextScaler.linear(
                            (mq ?? const MediaQueryData())
                                    .textScaler
                                    .scale(1.0) *
                                scale,
                          ),
                        ),
                        child: AnimatedQueryaTheme(
                          data: queryaTheme,
                          duration: themeDuration,
                          curve: themeCurve,
                          child: QueryaMotionScope(
                            level: motionLevel,
                            child: child ?? const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    );
                  },
                  home: const AppLifecycleCleanup(
                    child: MainScreen(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
