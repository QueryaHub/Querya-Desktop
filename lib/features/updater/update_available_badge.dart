import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';
import 'package:querya_desktop/features/updater/update_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Pulsing title-bar chip when a background update check finds a newer release.
class UpdateAvailableBadge extends material.StatefulWidget {
  const UpdateAvailableBadge({super.key, required this.controller});

  final UpdateController controller;

  @override
  material.State<UpdateAvailableBadge> createState() =>
      _UpdateAvailableBadgeState();
}

class _UpdateAvailableBadgeState extends material.State<UpdateAvailableBadge>
    with material.SingleTickerProviderStateMixin {
  late final material.AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = material.AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant UpdateAvailableBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
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
                padding:
                    const material.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: material.BoxDecoration(
                  color: wb.accent.withValues(alpha: 0.12 + 0.08 * _pulse.value),
                  borderRadius: material.BorderRadius.circular(999),
                  border: material.Border.all(
                    color: wb.accent.withValues(alpha: 0.35 + 0.25 * _pulse.value),
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
