import 'package:flutter/material.dart' as material;
import 'package:path/path.dart' as p;
import 'package:querya_desktop/shared/widgets/widgets.dart';

class ExtensionSideloadRequest {
  const ExtensionSideloadRequest({
    required this.archivePath,
    this.sha256Checksum,
  });

  final String archivePath;
  final String? sha256Checksum;
}

Future<ExtensionSideloadRequest?> showExtensionSideloadDialog(
  material.BuildContext context, {
  required String archivePath,
}) async {
  return showAppDialog<ExtensionSideloadRequest>(
    context: context,
    builder: (dialogContext) => _ExtensionSideloadDialog(
      archivePath: archivePath,
    ),
  );
}

class _ExtensionSideloadDialog extends material.StatefulWidget {
  const _ExtensionSideloadDialog({required this.archivePath});

  final String archivePath;

  @override
  material.State<_ExtensionSideloadDialog> createState() =>
      _ExtensionSideloadDialogState();
}

class _ExtensionSideloadDialogState
    extends material.State<_ExtensionSideloadDialog> {
  final _checksumController = material.TextEditingController();

  @override
  void dispose() {
    _checksumController.dispose();
    super.dispose();
  }

  void _submit() {
    final checksum = _checksumController.text.trim();
    material.Navigator.pop(
      context,
      ExtensionSideloadRequest(
        archivePath: widget.archivePath,
        sha256Checksum: checksum.isEmpty ? null : checksum,
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fileName = p.basename(widget.archivePath);

    return material.AlertDialog(
      title: const material.Text('Install local extension'),
      content: material.SizedBox(
        width: 440,
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Text('File: $fileName'),
            const material.SizedBox(height: 12),
            material.Container(
              width: double.infinity,
              padding: const material.EdgeInsets.all(12),
              decoration: material.BoxDecoration(
                color: cs.muted.withValues(alpha: 0.35),
                borderRadius: material.BorderRadius.circular(8),
                border: material.Border.all(color: cs.border),
              ),
              child: material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.Icon(
                    material.Icons.warning_amber_rounded,
                    size: 18,
                    color: cs.mutedForeground,
                  ),
                  const material.SizedBox(width: 10),
                  material.Expanded(
                    child: material.Text(
                      'Local packages are not verified unless you provide a '
                      'SHA-256 checksum. Only install archives from sources you '
                      'trust.',
                      style: material.TextStyle(
                        fontSize: 13,
                        color: cs.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const material.SizedBox(height: 12),
            material.TextField(
              controller: _checksumController,
              decoration: const material.InputDecoration(
                labelText: 'SHA-256 checksum (optional)',
                hintText: '64-character hex digest from publisher',
              ),
              autocorrect: false,
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => material.Navigator.pop(context),
          child: const material.Text('Cancel'),
        ),
        PrimaryButton(
          onPressed: _submit,
          child: const material.Text('Install'),
        ),
      ],
    );
  }
}
