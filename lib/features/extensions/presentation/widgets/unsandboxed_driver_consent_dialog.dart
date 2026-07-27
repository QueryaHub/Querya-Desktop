import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/sandbox/sandbox_os_isolation.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

Future<bool> showUnsandboxedDriverConsentDialog(
  material.BuildContext context,
  SandboxOsIsolationUnavailableException details,
) async {
  final approved = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => material.AlertDialog(
      title: const material.Text('Run driver without OS sandbox?'),
      content: material.SizedBox(
        width: 440,
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Text(details.message),
            if (details.installHint != null) ...[
              const material.SizedBox(height: 12),
              material.Text(
                details.installHint!,
                style: material.TextStyle(
                  fontSize: 13,
                  color: Theme.of(dialogContext).colorScheme.mutedForeground,
                ),
              ),
            ],
            const material.SizedBox(height: 12),
            const material.Text(
              'The driver process may access your user session (files, network) '
              'beyond the extension manifest policy. Only continue if you trust '
              'this extension package.',
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => material.Navigator.pop(dialogContext, false),
          child: const material.Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: () => material.Navigator.pop(dialogContext, true),
          child: const material.Text('Run without OS sandbox'),
        ),
      ],
    ),
  );
  return approved == true;
}
