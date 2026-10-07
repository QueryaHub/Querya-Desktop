import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';

/// Accent color for [environment]: green / yellow / red.
material.Color environmentAccentColor(
  QueryaWorkbenchTheme wb,
  ConnectionEnvironment environment,
) =>
    switch (environment) {
      ConnectionEnvironment.development => wb.success,
      ConnectionEnvironment.staging => wb.warning,
      ConnectionEnvironment.production => wb.destructive,
    };

/// Like [environmentAccentColor], but falls back to fixed colors when no
/// [QueryaThemeScope] is mounted (isolated form / dialog tests).
material.Color environmentAccentColorOf(
  material.BuildContext context,
  ConnectionEnvironment environment,
) {
  final wb = QueryaThemeScope.maybeOf(context)?.workbench;
  if (wb != null) return environmentAccentColor(wb, environment);
  return switch (environment) {
    ConnectionEnvironment.development => const material.Color(0xFF4CAF50),
    ConnectionEnvironment.staging => const material.Color(0xFFF59E0B),
    ConnectionEnvironment.production => const material.Color(0xFFEF4444),
  };
}

/// Background for window chrome (title / status bar) of a connection in
/// [environment]: [base] untouched for Development, tinted for the others.
material.Color environmentChromeColor(
  QueryaWorkbenchTheme wb,
  ConnectionEnvironment? environment,
  material.Color base,
) {
  switch (environment) {
    case ConnectionEnvironment.production:
      return material.Color.alphaBlend(
        environmentAccentColor(wb, environment!).withValues(alpha: 0.2),
        base,
      );
    case ConnectionEnvironment.staging:
      return material.Color.alphaBlend(
        environmentAccentColor(wb, environment!).withValues(alpha: 0.1),
        base,
      );
    case ConnectionEnvironment.development:
    case null:
      return base;
  }
}

/// Small colored pill with the environment tag (`DEV`, `STAGING`, `PROD`).
class ConnectionEnvironmentBadge extends material.StatelessWidget {
  const ConnectionEnvironmentBadge({
    super.key,
    required this.environment,
    this.compact = false,
  });

  final ConnectionEnvironment environment;

  /// Smaller padding and text, for the status bar.
  final bool compact;

  @override
  material.Widget build(material.BuildContext context) {
    final color = environmentAccentColor(context.workbench, environment);
    final fontSize = compact ? 9.0 : 10.5;
    return material.Tooltip(
      message: '${environment.label} environment',
      child: material.Semantics(
        label: '${environment.label} environment',
        child: material.Container(
          key: material.Key('environment_badge_${environment.storageValue}'),
          padding: material.EdgeInsets.symmetric(
            horizontal: context.scaled(compact ? 5 : 7),
            vertical: context.scaled(compact ? 1 : 2),
          ),
          decoration: material.BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: material.BorderRadius.circular(4),
            border: material.Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: material.Text(
            environment.badge,
            style: material.TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: material.FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
