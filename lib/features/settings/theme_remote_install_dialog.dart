import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Dialog for installing a theme from a public HTTPS URL.
Future<ThemeRemoteInstallRequest?> showThemeRemoteInstallDialog(
  material.BuildContext context,
) async {
  return showAppDialog<ThemeRemoteInstallRequest>(
    context: context,
    builder: (dialogContext) => const _ThemeRemoteInstallDialog(),
  );
}

class ThemeRemoteInstallRequest {
  const ThemeRemoteInstallRequest({
    required this.url,
    this.sha256Checksum,
  });

  final String url;
  final String? sha256Checksum;
}

class _ThemeRemoteInstallDialog extends material.StatefulWidget {
  const _ThemeRemoteInstallDialog();

  @override
  material.State<_ThemeRemoteInstallDialog> createState() =>
      _ThemeRemoteInstallDialogState();
}

class _ThemeRemoteInstallDialogState
    extends material.State<_ThemeRemoteInstallDialog> {
  final _urlController = material.TextEditingController();
  final _checksumController = material.TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _urlController.dispose();
    _checksumController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _validationError = 'Enter a theme URL.');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      setState(() => _validationError = 'Enter a valid HTTPS URL.');
      return;
    }
    if (uri.scheme != 'https') {
      setState(() => _validationError = 'Only HTTPS URLs are allowed.');
      return;
    }

    final checksum = _checksumController.text.trim();
    material.Navigator.pop(
      context,
      ThemeRemoteInstallRequest(
        url: url,
        sha256Checksum: checksum.isEmpty ? null : checksum,
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final host = Uri.tryParse(_urlController.text.trim())?.host;

    return QueryaModalDialog(
      title: const material.Text('Install theme from URL'),
      content: material.SizedBox(
        width: 420,
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            const material.Text(
              'Download runs only after you confirm. Use public HTTPS links.',
            ),
            if (host != null && host.isNotEmpty) ...[
              const material.SizedBox(height: 8),
              material.Text(
                'Host: $host',
                style: material.TextStyle(
                  fontSize: 12,
                  color: cs.mutedForeground,
                ),
              ),
            ],
            const material.SizedBox(height: 12),
            const Text('Theme URL').small().semiBold(),
            const Gap(6),
            QueryaTextField(
              controller: _urlController,
              placeholder: 'https://example.com/themes/my-theme.json',
              keyboardType: material.TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() => _validationError = null),
            ),
            const material.SizedBox(height: 12),
            const Text('SHA-256 checksum (optional)').small().semiBold(),
            const Gap(6),
            QueryaTextField(
              controller: _checksumController,
              placeholder: 'hex digest or ?sha256= on URL',
              autocorrect: false,
            ),
            if (_validationError != null) ...[
              const material.SizedBox(height: 8),
              material.Text(
                _validationError!,
                style: material.TextStyle(
                  fontSize: 12,
                  color: cs.destructive,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        QueryaButton.ghost(
          label: 'Cancel',
          onPressed: () => material.Navigator.pop(context),
          size: QueryaControlSize.lg,
        ),
        QueryaButton.primary(
          label: 'Install',
          onPressed: _submit,
          size: QueryaControlSize.lg,
        ),
      ],
    );
  }
}
