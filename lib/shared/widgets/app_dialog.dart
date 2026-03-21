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
        child: builder(ctx),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ),
        child: child,
      );
    },
  );
}

class _BlurredDialogScaffold extends StatelessWidget {
  const _BlurredDialogScaffold({
    required this.barrierDismissible,
    required this.onDismiss,
    required this.child,
  });

  final bool barrierDismissible;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: barrierDismissible ? onDismiss : null,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.32),
                  ),
                ),
              ),
            ),
          ),
          Center(child: child),
        ],
      ),
    );
  }
}
