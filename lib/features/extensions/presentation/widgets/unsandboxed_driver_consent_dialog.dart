import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/sandbox/sandbox_os_isolation.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

Future<bool> showUnsandboxedDriverConsentDialog(
  material.BuildContext context,
  SandboxOsIsolationUnavailableException details,
) async {
  final approved = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => QueryaModalDialog(
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
                  color: dialogContext.colors.mutedForeground,
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
        QueryaButton.ghost(
          label: 'Cancel',
          onPressed: () => material.Navigator.pop(dialogContext, false),
          size: QueryaControlSize.lg,
        ),
        QueryaButton.primary(
          label: 'Run without OS sandbox',
          onPressed: () => material.Navigator.pop(dialogContext, true),
          size: QueryaControlSize.lg,
        ),
      ],
    ),
  );
  return approved == true;
}
