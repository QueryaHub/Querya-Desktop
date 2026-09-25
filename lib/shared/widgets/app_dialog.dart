import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';

/// Shows a modal dialog with a frosted, dimmed backdrop over the app.
///
/// Use instead of [showDialog] so every overlay has consistent blur.
/// Enter: fade + slight slide; exit uses [QueryaMotion.exit] via reverseCurve.
///
/// When [barrierDismissible] is true (default), Escape and backdrop tap dismiss.
/// Escape is handled by the modal route; backdrop tap by [_BlurredDialogScaffold]
/// (the route barrier stays transparent under the frosted layer).
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: context.motionDuration(QueryaMotion.standard),
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

class _BlurredDialogScaffold extends StatefulWidget {
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

  @override
  State<_BlurredDialogScaffold> createState() => _BlurredDialogScaffoldState();
}

class _BlurredDialogScaffoldState extends State<_BlurredDialogScaffold> {
  CurvedAnimation? _curved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildCurved();
  }

  @override
  void didUpdateWidget(covariant _BlurredDialogScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _rebuildCurved();
    }
  }

  void _rebuildCurved() {
    _curved?.dispose();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: context.motionCurve(QueryaMotion.enter),
      reverseCurve: context.motionCurve(QueryaMotion.exit),
    );
  }

  @override
  void dispose() {
    _curved?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved!;
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(curved);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop: blur strength and tint animate directly. No Opacity wraps
          // the BackdropFilter, so no extra full-screen offscreen layer is
          // composited on every frame of the enter / exit transition.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.barrierDismissible ? widget.onDismiss : null,
              child: AnimatedBuilder(
                animation: curved,
                builder: (ctx, _) => _DialogBackdrop(progress: curved.value),
              ),
            ),
          ),
          // Dialog card: fade-slide enter; exit uses reverseCurve (QueryaMotion.exit).
          Center(
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: slide,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted, dimmed dialog backdrop at [progress] (0 = none, 1 = full).
///
/// Both blur sigma and tint alpha scale with [progress], so the frost fades in
/// and out without pop-in and without an enclosing `Opacity`.
class _DialogBackdrop extends StatelessWidget {
  const _DialogBackdrop({required this.progress});

  /// Full-strength blur sigma.
  static const double sigma = 8;

  /// Full-strength tint alpha (black @ 0.32).
  static const double tintAlpha = 0.32;

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.expand();
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma * t, sigmaY: sigma * t),
        child: ColoredBox(
          color: const Color(0xFF000000).withValues(alpha: tintAlpha * t),
        ),
      ),
    );
  }
}
