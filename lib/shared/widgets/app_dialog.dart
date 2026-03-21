import 'dart:ui';

import 'package:flutter/material.dart';

/// Shows a modal dialog with a frosted, dimmed backdrop over the app.
///
/// Use instead of [showDialog] so every overlay has consistent blur.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _BlurredDialogScaffold(
        barrierDismissible: barrierDismissible,
        onDismiss: () => Navigator.of(ctx).pop(),
        animation: animation,
        child: builder(ctx),
      );
    },
    // Pass through — all animation is handled inside _BlurredDialogScaffold.
    // Do NOT wrap the whole page (including BackdropFilter) in a FadeTransition:
    // that made blur invisible at opacity=0 and caused it to pop in with a delay.
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

class _BlurredDialogScaffold extends StatelessWidget {
  const _BlurredDialogScaffold({
    required this.barrierDismissible,
    required this.onDismiss,
    required this.animation,
    required this.child,
  });

  final bool barrierDismissible;
  final VoidCallback onDismiss;
  final Animation<double> animation;
  final Widget child;

  // Eased curve for dialog card fade-in / scale-up.
  static final _curve = CurveTween(curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final curved = animation.drive(_curve);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Backdrop: animates blur sigma and dim alpha directly, without
          //    being wrapped in a FadeTransition, so blur starts immediately.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: barrierDismissible ? onDismiss : null,
              child: AnimatedBuilder(
                animation: curved,
                builder: (ctx, _) {
                  final t = curved.value;
                  return ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10.0 * t, sigmaY: 10.0 * t),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.32 * t),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // ── Dialog card: fades + scales up, independently of the backdrop.
          Center(
            child: AnimatedBuilder(
              animation: curved,
              builder: (ctx, inner) => FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                  child: inner,
                ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
