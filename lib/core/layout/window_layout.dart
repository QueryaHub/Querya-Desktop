import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';

/// Breakpoints and sizes derived from window / overlay size (desktop adaptive UI).
abstract class WindowLayout {
  WindowLayout._();

  static const double narrowWindowWidth = 720;
  static const double compactWindowWidth = 520;

  /// Horizontal inset for modal dialogs (clamped by screen).
  static double dialogHorizontalInset(double screenWidth) {
    return (screenWidth * 0.05).clamp(12.0, 48.0);
  }

  static double dialogVerticalInset(double screenHeight) {
    return (screenHeight * 0.04).clamp(12.0, 40.0);
  }

  /// Scaled [BoxConstraints] for modal dialogs (respects [QueryaUiScaleScope]).
  static BoxConstraints dialogConstraints(
    BuildContext context, {
    double? maxWidth,
    double? minWidth,
    double? maxHeight,
    double? minHeight,
  }) {
    return BoxConstraints(
      maxWidth: maxWidth != null ? context.scaled(maxWidth) : double.infinity,
      minWidth: minWidth != null ? context.scaled(minWidth) : 0,
      maxHeight: maxHeight != null ? context.scaled(maxHeight) : double.infinity,
      minHeight: minHeight != null ? context.scaled(minHeight) : 0,
    );
  }

  /// Fits a base dialog dimension into the viewport, then applies UI scale.
  static double scaledDialogExtent(
    BuildContext context, {
    required double screenExtent,
    required double insetTotal,
    required double baseMax,
    required double baseMin,
    double viewportFactor = 1.0,
  }) {
    final available = math.max(0.0, screenExtent - insetTotal);
    final base = math.min(baseMax, math.max(baseMin, available * viewportFactor));
    return math.min(context.scaled(base), available);
  }

  /// Use for [Dialog.insetPadding] / modal margins on small windows.
  static EdgeInsets dialogSymmetricInsets(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    return EdgeInsets.symmetric(
      horizontal: dialogHorizontalInset(mq.width),
      vertical: dialogVerticalInset(mq.height),
    );
  }

  /// "Select database" and similar pickers.
  static double newConnectionDialogMaxWidth(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final inset = dialogHorizontalInset(mq.width) * 2;
    return scaledDialogExtent(
      context,
      screenExtent: mq.width,
      insetTotal: inset,
      baseMax: 740,
      baseMin: 280,
      viewportFactor: 1.0,
    );
  }

  static double newConnectionDialogHeight(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final inset = dialogVerticalInset(mq.height) * 2;
    return scaledDialogExtent(
      context,
      screenExtent: mq.height,
      insetTotal: inset,
      baseMax: 580,
      baseMin: 320,
      viewportFactor: 0.78,
    );
  }

  static double newConnectionSidebarWidth(double dialogWidth) {
    if (dialogWidth < 400) return 88;
    if (dialogWidth < 520) return 108;
    if (dialogWidth < 640) return 124;
    return 140;
  }

  /// Grid area width (right of sidebar, inner padding applied separately).
  static int dbTypeGridCrossAxisCount(double gridInnerWidth) {
    if (gridInnerWidth >= 460) return 4;
    if (gridInnerWidth >= 240) return 2;
    return 1;
  }

  static double dbTypeCardHeight(BuildContext context, int crossAxisCount) {
    final base = switch (crossAxisCount) {
      4 => 144.0,
      2 => 138.0,
      _ => 132.0,
    };
    return context.scaled(base);
  }

  /// Empty workspace hero content max width (stays within viewport minus padding).
  static double heroContentMaxWidth(double viewportWidth) {
    final pad = heroHorizontalPadding(viewportWidth) * 2;
    final inner = math.max(0.0, viewportWidth - pad);
    return math.min(560, inner);
  }

  static double heroHorizontalPadding(double viewportWidth) {
    if (viewportWidth < compactWindowWidth) return 16;
    if (viewportWidth < narrowWindowWidth) return 22;
    return 28;
  }

  /// Mock window block height scales with available width.
  static double heroMockWindowHeight(double contentWidth) {
    return (contentWidth * 0.38).clamp(140.0, 220.0);
  }
}
