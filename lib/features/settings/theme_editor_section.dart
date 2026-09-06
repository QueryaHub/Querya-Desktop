import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/settings/theme_editor_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

export 'package:querya_desktop/features/settings/theme_editor_dialog.dart'
    show showThemeEditorDialog, ThemeEditorDialog;

/// Launcher card in Preferences → Appearance for opening the focused Theme Studio modal.
class ThemeEditorSection extends material.StatelessWidget {
  const ThemeEditorSection({super.key});

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return material.Container(
      margin: const material.EdgeInsets.only(top: 12),
      padding: const material.EdgeInsets.all(14),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.18),
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color: cs.border.withValues(alpha: 0.28),
        ),
      ),
      child: material.Row(
        children: [
          material.Container(
            padding: const material.EdgeInsets.all(8),
            decoration: material.BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: material.BorderRadius.circular(6),
            ),
            child: material.Icon(
              material.Icons.palette_outlined,
              size: 20,
              color: cs.primary,
            ),
          ),
          const material.SizedBox(width: 12),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                const Text('Theme Studio').semiBold().small().foreground(),
                const material.SizedBox(height: 2),
                const Text(
                  'Fine-tune workbench and syntax highlight colors with live preview.',
                ).muted().xSmall(),
              ],
            ),
          ),
          const material.SizedBox(width: 12),
          OutlineButton(
            onPressed: () => unawaited(showThemeEditorDialog(context)),
            child: const material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(
                  material.Icons.tune_rounded,
                  size: 14,
                ),
                material.SizedBox(width: 6),
                material.Text('Edit theme colors…'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
