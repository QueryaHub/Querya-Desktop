import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Simple color picker dialog for the theme editor.
Future<Color?> showThemeColorPickerDialog({
  required material.BuildContext context,
  required Color initial,
}) async {
  var picked = ColorDerivative.fromColor(initial);

  return showAppDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return material.AlertDialog(
        title: const material.Text('Pick color'),
        content: material.SizedBox(
          width: 320,
          height: 360,
          child: ColorPicker(
            value: picked,
            onChanged: (value) => picked = value,
          ),
        ),
        actions: [
          material.TextButton(
            onPressed: () => material.Navigator.pop(dialogContext),
            child: const material.Text('Cancel'),
          ),
          material.TextButton(
            onPressed: () =>
                material.Navigator.pop(dialogContext, picked.toColor()),
            child: const material.Text('Apply'),
          ),
        ],
      );
    },
  );
}
