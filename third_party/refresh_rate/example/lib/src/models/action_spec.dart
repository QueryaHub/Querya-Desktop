import 'package:flutter/material.dart';

class ActionSpec {
  const ActionSpec({
    required this.label,
    required this.accent,
    required this.outlined,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool outlined;
  final VoidCallback? onTap;
}
