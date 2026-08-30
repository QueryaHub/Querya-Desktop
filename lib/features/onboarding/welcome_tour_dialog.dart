import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows or toggles the interactive Welcome Tour dialog.
Future<void> showWelcomeTourDialog(
  material.BuildContext context, {
  material.VoidCallback? onLaunchDemo,
  material.VoidCallback? onGoHome,
}) {
  if (WelcomeTourDialog.isOpen) {
    WelcomeTourDialog.close();
    return Future.value();
  }

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

/// Visual keyboard keycap badge adapting to OS conventions (Cmd vs Ctrl).
class KbdBadge extends StatelessWidget {
  const KbdBadge(
    this.keys, {
    super.key,
    this.fontSize = 11,
  });

  final List<String> keys;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final wb = context.workbench;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return material.Row(
      mainAxisSize: material.MainAxisSize.min,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          material.Container(
            padding: const material.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: material.BoxDecoration(
              color: isDark
                  ? const material.Color(0xFF1E2024)
                  : const material.Color(0xFFF1F5F9),
              borderRadius: material.BorderRadius.circular(4),
              border: material.Border.all(
                color: wb.borderSubtle.withValues(alpha: 0.8),
              ),
              boxShadow: [
                material.BoxShadow(
                  color: material.Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  offset: const material.Offset(0, 1),
                  blurRadius: 1,
                ),
              ],
            ),
            child: Text(
              keys[i],
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: material.FontWeight.w600,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.foreground,
              ),
            ),
          ),
          if (i < keys.length - 1)
            material.Padding(
              padding: const material.EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: wb.mutedForeground,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class WelcomeTourDialog extends StatefulWidget {
  const WelcomeTourDialog({
    super.key,
    this.onLaunchDemo,
    this.onGoHome,
  });

  final material.VoidCallback? onLaunchDemo;
  final material.VoidCallback? onGoHome;

  static material.BuildContext? _activeContext;
  static bool get isOpen => _activeContext != null;

  static void close() {
    if (_activeContext != null) {
      if (material.Navigator.of(_activeContext!).canPop()) {
        material.Navigator.of(_activeContext!).pop();
      }
      _activeContext = null;
    }
  }

  @override
  State<WelcomeTourDialog> createState() => _WelcomeTourDialogState();
}

class _WelcomeTourDialogState extends State<WelcomeTourDialog> {
  int _currentStep = 0;
  static const int _totalSteps = 6;

  @override
  void initState() {
    super.initState();
    WelcomeTourDialog._activeContext = context;
  }

  @override
  void dispose() {
    if (WelcomeTourDialog._activeContext == context) {
      WelcomeTourDialog._activeContext = null;
    }
    super.dispose();
  }

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
        const material.SingleActivator(LogicalKeyboardKey.f1): _finish,
        const material.SingleActivator(
          LogicalKeyboardKey.keyH,
          control: true,
          shift: true,
        ): _finish,
        const material.SingleActivator(
          LogicalKeyboardKey.keyH,
          meta: true,
          shift: true,
        ): _finish,
      },
      child: QueryaDialogCard(
        constraints: WindowLayout.dialogConstraints(
          context,
          maxWidth: 640,
          minWidth: 460,
        ),
        child: material.AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: material.Alignment.topCenter,
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
          shortcutBadge: KbdBadge([cmdCtrl, 'N']),
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
          shortcutBadge: KbdBadge([cmdCtrl, 'B']),
          wb: wb,
        );
      case 2:
        return _TourSlideView(
          key: const ValueKey(2),
          icon: material.Icons.code_rounded,
          iconColor: const material.Color(0xFF3B82F6), // Blue
          title: 'Pro SQL Editor & Workspaces',
          description:
              'Execute scripts with $cmdCtrl+Enter or F5. Open multiple query tabs, format SQL with $cmdCtrl+Shift+F, and access persistent query history.',
          tipText:
              'Use $cmdCtrl+T or $cmdCtrl+Shift+N to spawn a fresh SQL editor tab.',
          shortcutBadge: KbdBadge(['F5', 'or', '$cmdCtrl+Enter']),
          wb: wb,
        );
      case 3:
        return _TourSlideView(
          key: const ValueKey(3),
          icon: material.Icons.table_chart_rounded,
          iconColor: const material.Color(0xFF10B981), // Emerald
          title: 'Interactive 2D Grid & DML Staging',
          description:
              'Edit cells in-place, select ranges with Shift+Click, and copy TSV data with $cmdCtrl+C. Staged changes are safely previewed with DML inspection before committing.',
          tipText:
              'Copied cell ranges paste directly into Google Sheets and Excel.',
          shortcutBadge: KbdBadge([cmdCtrl, 'C']),
          wb: wb,
        );
      case 4:
        return _TourSlideView(
          key: const ValueKey(4),
          icon: material.Icons.filter_alt_rounded,
          iconColor: const material.Color(0xFFF59E0B), // Amber
          title: 'Compound Filter Bar & Quick Calc',
          description:
              'Filter grid results with live autocomplete expressions. Toggle Groupings & Pivot panels with $cmdCtrl+G and inspect instant stats (Sum, Avg, Median) in the status bar.',
          tipText:
              'Press $cmdCtrl+F to focus the compound filter bar on any active grid.',
          shortcutBadge: KbdBadge([cmdCtrl, 'F']),
          wb: wb,
        );
      case 5:
      default:
        return _HotkeysMatrixSlideView(
          key: const ValueKey(5),
          cmdCtrl: cmdCtrl,
          wb: wb,
          onLaunchDemo: widget.onLaunchDemo != null ? _launchDemoAndClose : null,
          onGoHome: widget.onGoHome != null ? _goHomeAndClose : null,
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
    required this.wb,
  });

  final material.IconData icon;
  final material.Color iconColor;
  final String title;
  final String description;
  final String tipText;
  final Widget shortcutBadge;
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
                    shortcutBadge,
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
            color: wb.surface,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(
              color: wb.borderSubtle.withValues(alpha: 0.65),
            ),
          ),
          child: material.Row(
            children: [
              material.Container(
                padding: const material.EdgeInsets.all(4),
                decoration: material.BoxDecoration(
                  color: wb.accent.withValues(alpha: 0.15),
                  shape: material.BoxShape.circle,
                ),
                child: material.Icon(
                  material.Icons.lightbulb_rounded,
                  size: 14,
                  color: wb.accent,
                ),
              ),
              const material.SizedBox(width: 10),
              material.Expanded(
                child: Text(
                  tipText,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context)
                        .colorScheme
                        .foreground
                        .withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HotkeysMatrixSlideView extends StatelessWidget {
  const _HotkeysMatrixSlideView({
    super.key,
    required this.cmdCtrl,
    required this.wb,
    this.onLaunchDemo,
    this.onGoHome,
  });

  final String cmdCtrl;
  final QueryaWorkbenchTheme wb;
  final material.VoidCallback? onLaunchDemo;
  final material.VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        // Header banner
        material.Container(
          padding: const material.EdgeInsets.all(12),
          decoration: material.BoxDecoration(
            color: wb.canvas,
            borderRadius: material.BorderRadius.circular(10),
            border: material.Border.all(
              color: wb.borderSubtle.withValues(alpha: 0.5),
            ),
          ),
          child: material.Row(
            children: [
              material.Container(
                width: 36,
                height: 36,
                decoration: material.BoxDecoration(
                  color: const material.Color(0xFFEC4899).withValues(alpha: 0.15),
                  shape: material.BoxShape.circle,
                ),
                child: const material.Icon(
                  material.Icons.keyboard_rounded,
                  size: 20,
                  color: material.Color(0xFFEC4899),
                ),
              ),
              const material.SizedBox(width: 12),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    const Text('Keyboard Shortcuts Cheat Sheet').semiBold().base(),
                    const Text('Master Querya like a pro with instant key bindings.')
                        .muted()
                        .xSmall(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const material.SizedBox(height: 12),

        // Hotkeys Matrix Table
        material.Container(
          padding: const material.EdgeInsets.all(12),
          decoration: material.BoxDecoration(
            color: wb.surface,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(
              color: wb.borderSubtle.withValues(alpha: 0.6),
            ),
          ),
          child: material.Column(
            children: [
              _hotkeyRow(context, 'Run Query / Script', [cmdCtrl, 'Enter'], wb),
              const material.Divider(height: 10),
              _hotkeyRow(context, 'New Connection', [cmdCtrl, 'N'], wb),
              const material.Divider(height: 10),
              _hotkeyRow(context, 'Toggle Sidebar', [cmdCtrl, 'B'], wb),
              const material.Divider(height: 10),
              _hotkeyRow(context, 'Compound Filter Bar', [cmdCtrl, 'F'], wb),
              const material.Divider(height: 10),
              _hotkeyRow(context, 'Copy Selection (TSV)', [cmdCtrl, 'C'], wb),
              const material.Divider(height: 10),
              _hotkeyRow(context, 'Open Guide / Tour', ['F1'], wb),
            ],
          ),
        ),
        const material.SizedBox(height: 14),

        // Playground and Home buttons
        material.Row(
          children: [
            if (onLaunchDemo != null)
              material.Expanded(
                child: OutlineButton(
                  key: const Key('welcome_tour_demo_button'),
                  onPressed: onLaunchDemo,
                  leading: const material.Icon(
                    material.Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  child: const Text('Try Demo Playground'),
                ),
              ),
            if (onLaunchDemo != null && onGoHome != null)
              const material.SizedBox(width: 8),
            if (onGoHome != null)
              material.Expanded(
                child: GhostButton(
                  key: const Key('welcome_tour_slide_home_button'),
                  onPressed: onGoHome,
                  leading: const material.Icon(
                    material.Icons.home_rounded,
                    size: 16,
                  ),
                  child: const Text('Start Screen'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  material.Widget _hotkeyRow(
    material.BuildContext context,
    String label,
    List<String> keys,
    QueryaWorkbenchTheme wb,
  ) {
    return material.Row(
      mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.foreground,
            fontWeight: material.FontWeight.w500,
          ),
        ),
        KbdBadge(keys, fontSize: 10.5),
      ],
    );
  }
}
