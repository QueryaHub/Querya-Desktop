import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/connections/ssl_certificate_support.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Optional SSL certificate path fields (Root CA, client cert, client key).
class SslCertificateFields extends material.StatelessWidget {
  const SslCertificateFields({
    super.key,
    required this.rootCertController,
    required this.clientCertController,
    required this.clientKeyController,
    this.onChanged,
  });

  final material.TextEditingController rootCertController;
  final material.TextEditingController clientCertController;
  final material.TextEditingController clientKeyController;
  final VoidCallback? onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    return material.FocusTraversalGroup(
      policy: material.WidgetOrderTraversalPolicy(),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          const Text('SSL Certificates (optional)').small().semiBold(),
          const Gap(4),
          const Text(
            'Root CA, client certificate, and client key are appended to the '
            'connection URI.',
          ).muted().small(),
          const Gap(8),
          _SslFileField(
            label: 'Root CA / SSL Root Certificate',
            controller: rootCertController,
            onChanged: onChanged,
          ),
          const Gap(8),
          _SslFileField(
            label: 'SSL Client Certificate',
            controller: clientCertController,
            onChanged: onChanged,
          ),
          const Gap(8),
          _SslFileField(
            label: 'SSL Client Key',
            controller: clientKeyController,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SslFileField extends material.StatelessWidget {
  const _SslFileField({
    required this.label,
    required this.controller,
    this.onChanged,
  });

  final String label;
  final material.TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        Text(label).xSmall().muted(),
        const Gap(4),
        material.Row(
          children: [
            material.Expanded(
              child: TextField(
                key: Key(label),
                controller: controller,
                placeholder: const Text('/path/to/file.pem'),
                onChanged: onChanged == null ? null : (_) => onChanged!(),
              ),
            ),
            const Gap(8),
            GhostButton(
              onPressed: () async {
                await pickSslCertificateFile(
                  onPicked: (path) {
                    controller.text = path;
                    onChanged?.call();
                  },
                );
              },
              child: const Icon(material.Icons.folder_open_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

void populateSslControllersFromUri(
  String uriText, {
  required material.TextEditingController rootCertController,
  required material.TextEditingController clientCertController,
  required material.TextEditingController clientKeyController,
}) {
  if (uriText.trim().isEmpty) return;
  final parsed = Uri.tryParse(uriText.trim());
  if (parsed == null) return;
  final paths = extractSslCertificatePaths(parsed);
  rootCertController.text = paths.rootCert ?? '';
  clientCertController.text = paths.clientCert ?? '';
  clientKeyController.text = paths.clientKey ?? '';
}

bool hasSslCertificateControllerValues({
  required material.TextEditingController rootCertController,
  required material.TextEditingController clientCertController,
  required material.TextEditingController clientKeyController,
}) {
  return rootCertController.text.trim().isNotEmpty ||
      clientCertController.text.trim().isNotEmpty ||
      clientKeyController.text.trim().isNotEmpty;
}

SslCertificatePaths sslPathsFromControllers({
  required material.TextEditingController rootCertController,
  required material.TextEditingController clientCertController,
  required material.TextEditingController clientKeyController,
}) {
  return SslCertificatePaths(
    rootCert: rootCertController.text.trim(),
    clientCert: clientCertController.text.trim(),
    clientKey: clientKeyController.text.trim(),
  );
}

void syncSslControllersIntoUri(
  material.TextEditingController connectionStringController, {
  required material.TextEditingController rootCertController,
  required material.TextEditingController clientCertController,
  required material.TextEditingController clientKeyController,
}) {
  final uriText = connectionStringController.text.trim();
  if (uriText.isEmpty) return;
  final parsed = Uri.tryParse(uriText);
  if (parsed == null) return;
  final paths = sslPathsFromControllers(
    rootCertController: rootCertController,
    clientCertController: clientCertController,
    clientKeyController: clientKeyController,
  );
  connectionStringController.text =
      applySslCertificatePaths(parsed, paths).toString();
}
