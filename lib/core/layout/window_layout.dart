import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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

  /// Use for [Dialog.insetPadding] / modal margins on small windows.
  static EdgeInsets dialogSymmetricInsets(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    return EdgeInsets.symmetric(
      horizontal: dialogHorizontalInset(mq.width),
      vertical: dialogVerticalInset(mq.height),
    );
  }

  /// "Select database" and similar pickers.
  static double newConnectionDialogMaxWidth(double screenWidth) {
    final inset = dialogHorizontalInset(screenWidth) * 2;
    return math.min(740, math.max(280.0, screenWidth - inset));
  }

  static double newConnectionDialogHeight(double screenHeight) {
    final inset = dialogVerticalInset(screenHeight) * 2;
    final h = screenHeight - inset;
    return math.min(580, math.max(320.0, h * 0.78));
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

  static double dbTypeCardHeight(int crossAxisCount) {
    return switch (crossAxisCount) {
      4 => 144,
      2 => 138,
      _ => 132,
    };
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
