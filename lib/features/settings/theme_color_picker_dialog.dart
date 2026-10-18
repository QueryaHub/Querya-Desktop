import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Simple color picker dialog for the theme editor.
Future<Color?> showThemeColorPickerDialog({
  required material.BuildContext context,
  required Color initial,
}) async {
  var picked = initial;

  return showAppDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return QueryaModalDialog(
        title: const material.Text('Pick color'),
        content: material.SizedBox(
          width: 320,
          height: 300,
          child: QueryaColorPicker(
            value: picked,
            onChanged: (value) => picked = value,
          ),
        ),
        actions: [
          QueryaButton.ghost(
            label: 'Cancel',
            onPressed: () => material.Navigator.pop(dialogContext),
            size: QueryaControlSize.lg,
          ),
          QueryaButton.primary(
            label: 'Apply',
            onPressed: () =>
                material.Navigator.pop(dialogContext, picked),
            size: QueryaControlSize.lg,
          ),
        ],
      );
    },
  );
}
