import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows the interactive Welcome Tour dialog.
Future<void> showWelcomeTourDialog(
  material.BuildContext context, {
  material.VoidCallback? onLaunchDemo,
  material.VoidCallback? onGoHome,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(ctx),
      child: WelcomeTourDialog(
        onLaunchDemo: onLaunchDemo,
        onGoHome: onGoHome,
      ),
    ),
  );
}

class WelcomeTourDialog extends StatefulWidget {
  const WelcomeTourDialog({
    super.key,
    this.onLaunchDemo,
    this.onGoHome,
  });

  final material.VoidCallback? onLaunchDemo;
  final material.VoidCallback? onGoHome;

  @override
  State<WelcomeTourDialog> createState() => _WelcomeTourDialogState();
}

class _WelcomeTourDialogState extends State<WelcomeTourDialog> {
  int _currentStep = 0;
  static const int _totalSteps = 4;

  void _goToStep(int step) {
    if (step >= 0 && step < _totalSteps && step != _currentStep) {
      setState(() => _currentStep = step);
    }
  }

  void _next() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _finish();
    }
  }

  void _previous() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _finish() {
    unawaited(AppSettings.instance.setHasCompletedWelcomeTour(true));
    if (mounted && material.Navigator.of(context).canPop()) {
      material.Navigator.of(context).pop();
    }
  }

  void _launchDemoAndClose() {
    unawaited(AppSettings.instance.setHasCompletedWelcomeTour(true));
    if (mounted && material.Navigator.of(context).canPop()) {
      material.Navigator.of(context).pop();
    }
    widget.onLaunchDemo?.call();
  }

  void _goHomeAndClose() {
    unawaited(AppSettings.instance.setHasCompletedWelcomeTour(true));
    if (mounted && material.Navigator.of(context).canPop()) {
      material.Navigator.of(context).pop();
    }
    widget.onGoHome?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wb = context.workbench;

    final isMac = Platform.isMacOS;
    final cmdCtrl = isMac ? 'Cmd' : 'Ctrl';

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const material.SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
        const material.SingleActivator(LogicalKeyboardKey.enter): _next,
        const material.SingleActivator(LogicalKeyboardKey.escape): _finish,
      },
      child: QueryaDialogCard(
        constraints: WindowLayout.dialogConstraints(
          context,
          maxWidth: 580,
          minWidth: 420,
        ),
        child: material.Padding(
          padding: const material.EdgeInsets.all(24),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              // Header row
              material.Row(
                children: [
                  material.Container(
                    padding: const material.EdgeInsets.all(8),
                    decoration: material.BoxDecoration(
                      color: wb.accent.withValues(alpha: 0.15),
                      borderRadius: material.BorderRadius.circular(10),
                      border: material.Border.all(
                        color: wb.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: material.Icon(
                      material.Icons.auto_awesome_rounded,
                      size: 20,
                      color: wb.accent,
                    ),
                  ),
                  const material.SizedBox(width: 12),
                  material.Expanded(
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        const Text('Welcome to Querya').semiBold().large(),
                        Text('Step ${_currentStep + 1} of $_totalSteps')
                            .xSmall()
                            .muted(),
                      ],
                    ),
                  ),
                  if (widget.onGoHome != null) ...[
                    GhostButton(
                      key: const Key('welcome_tour_home_button'),
                      density: ButtonDensity.compact,
                      onPressed: _goHomeAndClose,
                      leading: const material.Icon(
                        material.Icons.home_rounded,
                        size: 16,
                      ),
                      child: const Text('Home'),
                    ),
                    const material.SizedBox(width: 4),
                  ],
                  material.IconButton(
                    icon: const material.Icon(
                      material.Icons.close_rounded,
                      size: 18,
                    ),
                    tooltip: 'Close',
                    splashRadius: 16,
                    onPressed: _finish,
                  ),
                ],
              ),
              const material.SizedBox(height: 18),

              // Animated Slide body
              material.AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return material.FadeTransition(
                    opacity: animation,
                    child: material.SlideTransition(
                      position: material.Tween<material.Offset>(
                        begin: const material.Offset(0.04, 0),
                        end: material.Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _buildSlideContent(
                  step: _currentStep,
                  cmdCtrl: cmdCtrl,
                  cs: cs,
                  wb: wb,
                ),
              ),
              const material.SizedBox(height: 20),

              // Footer controls & Step dots
              material.Row(
                children: [
                  // Step indicator dots (clickable)
                  material.Row(
                    mainAxisSize: material.MainAxisSize.min,
                    children: List.generate(_totalSteps, (index) {
                      final active = index == _currentStep;
                      return material.GestureDetector(
                        onTap: () => _goToStep(index),
                        behavior: material.HitTestBehavior.opaque,
                        child: material.Container(
                          padding: const material.EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 6,
                          ),
                          child: material.AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            width: active ? 22 : 6,
                            height: 6,
                            decoration: material.BoxDecoration(
                              color: active
                                  ? wb.accent
                                  : wb.mutedForeground.withValues(alpha: 0.3),
                              borderRadius: material.BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const material.Spacer(),

                  // Action buttons
                  if (_currentStep > 0)
                    OutlineButton(
                      key: const Key('welcome_tour_prev_button'),
                      onPressed: _previous,
                      child: const Text('Back'),
                    )
                  else
                    GhostButton(
                      key: const Key('welcome_tour_skip_button'),
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  const material.SizedBox(width: 8),

                  PrimaryButton(
                    key: const Key('welcome_tour_next_button'),
                    onPressed: _next,
                    child: Text(
                      _currentStep == _totalSteps - 1
                          ? 'Get Started'
                          : 'Next',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlideContent({
    required int step,
    required String cmdCtrl,
    required ColorScheme cs,
    required QueryaWorkbenchTheme wb,
  }) {
    switch (step) {
      case 0:
        return _TourSlideView(
          key: const ValueKey(0),
          icon: material.Icons.hub_rounded,
          iconColor: const material.Color(0xFF06B6D4), // Cyan
          title: 'Connect in Seconds',
          description:
              'Connect directly to PostgreSQL, MySQL, SQLite, Redis, MongoDB or custom extension drivers. Paste a connection URL or use our visual form with real-time field validation.',
          tipText: 'Press $cmdCtrl+N anytime to create a new connection.',
          shortcutBadge: '$cmdCtrl+N',
          wb: wb,
        );
      case 1:
        return _TourSlideView(
          key: const ValueKey(1),
          icon: material.Icons.view_sidebar_rounded,
          iconColor: const material.Color(0xFF8B5CF6), // Purple
          title: 'Fluid Sidebar & Navigation',
          description:
              'Browse database schemas, tables, and views with full keyboard navigation. Right-click any object for instant SELECT queries and DDL copy.',
          tipText:
              'Collapse the sidebar with $cmdCtrl+B for an expansive full-screen workspace.',
          shortcutBadge: '$cmdCtrl+B',
          wb: wb,
        );
      case 2:
        return _TourSlideView(
          key: const ValueKey(2),
          icon: material.Icons.table_chart_rounded,
          iconColor: const material.Color(0xFF10B981), // Emerald
          title: 'Interactive SQL & 2D Grid',
          description:
              'Run queries instantly with $cmdCtrl+Enter. Sort results by clicking headers, drag column borders to resize, and Shift+Click to copy cell ranges in TSV format.',
          tipText:
              'Copied cell ranges paste directly into Google Sheets and Excel.',
          shortcutBadge: '$cmdCtrl+Enter',
          wb: wb,
        );
      case 3:
      default:
        return _TourSlideView(
          key: const ValueKey(3),
          icon: material.Icons.shield_rounded,
          iconColor: const material.Color(0xFFF59E0B), // Amber
          title: 'Zero-Trust Security & Playground',
          description:
              'Database credentials stay protected inside your operating system secure keychain. Try our 1-click Demo Playground to explore Querya instantly without server setup.',
          tipText:
              'Toggle Read-Only mode in the title bar for risk-free production exploration.',
          shortcutBadge: 'Protected',
          actionButtons: [
            if (widget.onLaunchDemo != null)
              OutlineButton(
                key: const Key('welcome_tour_demo_button'),
                onPressed: _launchDemoAndClose,
                leading: const material.Icon(
                  material.Icons.play_arrow_rounded,
                  size: 18,
                ),
                child: const Text('Try Demo Playground Now'),
              ),
            if (widget.onGoHome != null) ...[
              const material.SizedBox(height: 8),
              GhostButton(
                key: const Key('welcome_tour_slide_home_button'),
                onPressed: _goHomeAndClose,
                leading: const material.Icon(
                  material.Icons.home_rounded,
                  size: 16,
                ),
                child: const Text('Return to Start Screen'),
              ),
            ],
          ],
          wb: wb,
        );
    }
  }
}

class _TourSlideView extends StatelessWidget {
  const _TourSlideView({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.tipText,
    required this.shortcutBadge,
    this.actionButtons,
    required this.wb,
  });

  final material.IconData icon;
  final material.Color iconColor;
  final String title;
  final String description;
  final String tipText;
  final String shortcutBadge;
  final List<Widget>? actionButtons;
  final QueryaWorkbenchTheme wb;

  @override
  Widget build(BuildContext context) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        // Graphic & Badge banner
        material.Container(
          padding: const material.EdgeInsets.all(16),
          decoration: material.BoxDecoration(
            color: wb.canvas,
            borderRadius: material.BorderRadius.circular(12),
            border: material.Border.all(
              color: wb.borderSubtle.withValues(alpha: 0.5),
            ),
            gradient: material.LinearGradient(
              begin: material.Alignment.topLeft,
              end: material.Alignment.bottomRight,
              colors: [
                wb.canvas,
                wb.surface.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: material.Row(
            children: [
              material.Container(
                width: 44,
                height: 44,
                decoration: material.BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: material.BoxShape.circle,
                  border: material.Border.all(
                    color: iconColor.withValues(alpha: 0.35),
                  ),
                ),
                child: material.Icon(
                  icon,
                  size: 24,
                  color: iconColor,
                ),
              ),
              const material.SizedBox(width: 14),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    Text(title).semiBold().base(),
                    const material.SizedBox(height: 4),
                    material.Container(
                      padding: const material.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: material.BoxDecoration(
                        color: wb.surface,
                        borderRadius: material.BorderRadius.circular(6),
                        border: material.Border.all(
                          color: wb.borderSubtle.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        shortcutBadge,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: material.FontWeight.w600,
                          color: wb.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const material.SizedBox(height: 14),

        // Description
        Text(
          description,
          style: TextStyle(
            color: wb.mutedForeground,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const material.SizedBox(height: 12),

        // Tip banner
        material.Container(
          padding: const material.EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: material.BoxDecoration(
            color: wb.accent.withValues(alpha: 0.08),
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(
              color: wb.accent.withValues(alpha: 0.2),
            ),
          ),
          child: material.Row(
            children: [
              material.Icon(
                material.Icons.lightbulb_outline_rounded,
                size: 16,
                color: wb.accent,
              ),
              const material.SizedBox(width: 8),
              material.Expanded(
                child: Text(
                  tipText,
                  style: TextStyle(
                    fontSize: 12,
                    color: wb.onAccent,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (actionButtons != null && actionButtons!.isNotEmpty) ...[
          const material.SizedBox(height: 14),
          ...actionButtons!,
        ],
      ],
    );
  }
}
