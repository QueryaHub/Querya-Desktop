import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

enum AppToastVariant {
  info,
  success,
  error,
}

/// Shows non-blocking app feedback using the shared shadcn toast layer.
shadcn.ToastOverlay showAppToast({
  required material.BuildContext context,
  required String message,
  AppToastVariant variant = AppToastVariant.info,
  Duration showDuration = const Duration(seconds: 5),
}) {
  final isError = variant == AppToastVariant.error;
  final motionDuration = context.motionDuration(QueryaMotion.standard);
  // shadcn's toast removal callback cannot complete synchronously during build.
  // One microsecond remains effectively instant while deferring that callback.
  final entryDuration = motionDuration == Duration.zero
      ? const Duration(microseconds: 1)
      : motionDuration;
  final icon = switch (variant) {
    AppToastVariant.info => material.Icons.info_outline_rounded,
    AppToastVariant.success => material.Icons.check_circle_outline_rounded,
    AppToastVariant.error => material.Icons.error_outline_rounded,
  };

  return shadcn.showToast(
    context: context,
    location: shadcn.ToastLocation.bottomRight,
    entryDuration: entryDuration,
    curve: context.motionCurve(QueryaMotion.enter),
    showDuration: showDuration,
    builder: (context, overlay) => shadcn.Alert(
      destructive: isError,
      leading: material.Icon(icon, size: 18),
      title: material.Text(message),
      trailing: shadcn.GhostButton(
        size: shadcn.ButtonSize.small,
        onPressed: overlay.close,
        child: const material.Icon(material.Icons.close_rounded, size: 16),
      ),
    ),
  );
}
