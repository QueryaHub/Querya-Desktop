import 'package:flutter/material.dart' as material;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:querya_desktop/core/app/external_link.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows the About Querya dialog.
Future<void> showAboutDialog(material.BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: const _AboutDialogContent(),
    ),
  );
}

class _AboutDialogContent extends material.StatefulWidget {
  const _AboutDialogContent();

  @override
  material.State<_AboutDialogContent> createState() =>
      _AboutDialogContentState();
}

class _AboutDialogContentState extends material.State<_AboutDialogContent> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final wb = context.workbench;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 420,
        minWidth: 320,
      ),
      borderColor: theme.muted,
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(24, 28, 24, 8),
            child: material.Column(
              children: [
                material.Icon(
                  QueryaIcons.database,
                  size: 48,
                  color: wb.accent,
                ),
                const material.SizedBox(height: 16),
                const Text('Querya').large().semiBold(),
                const material.SizedBox(height: 8),
                FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? '…';
                    return Text('Version $version').muted().small();
                  },
                ),
                const material.SizedBox(height: 16),
                const Text(
                  'A lightweight desktop SQL/NoSQL client.',
                ).muted().small(),
                const material.SizedBox(height: 12),
                const Text(
                  'Licensed under the MIT License.',
                ).small(),
                const material.SizedBox(height: 16),
                GhostButton(
                  onPressed: () => launchRepositoryUrl(),
                  child: const Text('View repository'),
                ),
              ],
            ),
          ),
          material.Container(
            padding: const material.EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            decoration: material.BoxDecoration(
              border: material.Border(
                top: material.BorderSide(
                  color: theme.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: material.Row(
              mainAxisAlignment: material.MainAxisAlignment.end,
              children: [
                PrimaryButton(
                  onPressed: () => material.Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens project documentation in the system browser.
Future<bool> openQueryaDocumentation() => launchDocumentationUrl();
