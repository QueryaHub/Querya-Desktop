import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';
import 'package:querya_desktop/features/updater/update_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Soft pulse period for the update chip (documented chrome constant; see F9).
const Duration kUpdateBadgePulsePeriod = Duration(milliseconds: 1400);

/// Pulsing title-bar chip when a background update check finds a newer release.
class UpdateAvailableBadge extends material.StatefulWidget {
  const UpdateAvailableBadge({super.key, required this.controller});

  final UpdateController controller;

  @override
  UpdateAvailableBadgeState createState() => UpdateAvailableBadgeState();
}

class UpdateAvailableBadgeState extends material.State<UpdateAvailableBadge>
    with material.SingleTickerProviderStateMixin {
  late final material.AnimationController _pulse;

  @visibleForTesting
  bool get isPulseAnimating => _pulse.isAnimating;

  @override
  void initState() {
    super.initState();
    _pulse = material.AnimationController(
      vsync: this,
      duration: kUpdateBadgePulsePeriod,
    );
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant UpdateAvailableBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _syncPulse();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _syncPulse();
  }

  void _syncPulse() {
    final show = widget.controller.showBadge;
    final motionOff =
        QueryaMotionScope.maybeOf(context) == QueryaMotionLevel.off ||
            material.MediaQuery.disableAnimationsOf(context);
    if (!show || motionOff) {
      if (_pulse.isAnimating) {
        _pulse.stop();
      }
      _pulse.value = 0;
      return;
    }
    if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _pulse.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (!widget.controller.showBadge) {
      return const material.SizedBox.shrink();
    }

    final version = widget.controller.pendingUpdate?.version ?? '';
    final wb = context.workbench;
    // Depend on motion so Off/Reduced rebuilds re-sync the pulse.
    context.motionDuration(QueryaMotion.fast);

    return material.Padding(
      padding: const material.EdgeInsets.only(right: 8),
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          borderRadius: material.BorderRadius.circular(999),
          onTap: () => unawaited(
            showUpdateDialog(
              context,
              initialManifest: widget.controller.pendingUpdate,
            ),
          ),
          child: material.AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              return material.Container(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: material.BoxDecoration(
                  color:
                      wb.accent.withValues(alpha: 0.12 + 0.08 * _pulse.value),
                  borderRadius: material.BorderRadius.circular(999),
                  border: material.Border.all(
                    color:
                        wb.accent.withValues(alpha: 0.35 + 0.25 * _pulse.value),
                  ),
                ),
                child: child,
              );
            },
            child: material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(
                  material.Icons.card_giftcard_rounded,
                  size: 14,
                  color: wb.accent,
                ),
                const material.SizedBox(width: 6),
                Text('v$version available').xSmall().semiBold(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
