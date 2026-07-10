import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

class ExtensionCard extends material.StatelessWidget {
  const ExtensionCard({
    super.key,
    required this.manifest,
    required this.isInstalled,
    this.hasUpdate = false,
    this.isInstalling = false,
    this.installProgress,
    this.onInstall,
    this.onUninstall,
    this.onUpdate,
  });

  final ExtensionManifest manifest;
  final bool isInstalled;
  final bool hasUpdate;
  final bool isInstalling;
  final double? installProgress;
  final material.VoidCallback? onInstall;
  final material.VoidCallback? onUninstall;
  final material.VoidCallback? onUpdate;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusMd;
    final isPreview = ExtensionSupport.isPreviewOnlyManifest(manifest);
    
    return material.Container(
      padding: const material.EdgeInsets.all(16),
      decoration: material.BoxDecoration(
        color: theme.card,
        border: material.Border.all(color: theme.border),
        borderRadius: material.BorderRadius.circular(radius),
      ),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          _buildIcon(theme, radius),
          const material.SizedBox(width: 16),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Row(
                  children: [
                    material.Expanded(
                      child: Text(manifest.name).large().semiBold(),
                    ),
                    if (isPreview) ...[
                      const material.SizedBox(width: 8),
                      _buildPreviewBadge(theme),
                    ],
                  ],
                ),
                const material.SizedBox(height: 4),
                material.Row(
                  children: [
                    Text(manifest.publisher).muted().small(),
                    const material.SizedBox(width: 8),
                    material.Container(
                      width: 4,
                      height: 4,
                      decoration: material.BoxDecoration(
                        color: theme.mutedForeground,
                        shape: material.BoxShape.circle,
                      ),
                    ),
                    const material.SizedBox(width: 8),
                    Text('v${manifest.version}').muted().small(),
                  ],
                ),
                const material.SizedBox(height: 8),
                Text(
                  manifest.description ?? 'No description provided.',
                  maxLines: 2,
                  overflow: material.TextOverflow.ellipsis,
                ).muted(),
                if (manifest.tags.isNotEmpty) ...[
                  const material.SizedBox(height: 10),
                  material.Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: manifest.tags
                        .take(5)
                        .map((tag) => _buildTagBadge(theme, tag))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const material.SizedBox(width: 16),
          material.Column(
            mainAxisAlignment: material.MainAxisAlignment.center,
            crossAxisAlignment: material.CrossAxisAlignment.end,
            children: [
              if (isInstalled && hasUpdate && !isInstalling)
                material.Padding(
                  padding: const material.EdgeInsets.only(bottom: 8.0),
                  child: PrimaryButton(
                    onPressed: onUpdate,
                    child: const Text('Update'),
                  ),
                ),
              if (isInstalling)
                material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.end,
                  children: [
                    material.SizedBox(
                      width: 110,
                      child: material.LinearProgressIndicator(
                        value: installProgress,
                        backgroundColor: theme.muted,
                        color: theme.primary,
                        minHeight: 6,
                        borderRadius: material.BorderRadius.circular(3),
                      ),
                    ),
                    const material.SizedBox(height: 6),
                    Text(installProgress != null
                            ? 'Installing ${(installProgress! * 100).toInt()}%'
                            : 'Installing...')
                        .muted()
                        .small(),
                  ],
                )
              else if (isInstalled)
                SecondaryButton(
                  onPressed: onUninstall,
                  child: const Text('Uninstall'),
                )
              else if (isPreview)
                const material.Tooltip(
                  message: ExtensionSupport.databaseDriverPreviewNotice,
                  child: OutlineButton(
                    onPressed: null,
                    child: Text('Preview'),
                  ),
                )
              else
                PrimaryButton(
                  onPressed: onInstall,
                  child: const Text('Install'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  material.Widget _buildIcon(ColorScheme theme, double radius) {
    return material.Container(
      width: 48,
      height: 48,
      decoration: material.BoxDecoration(
        color: theme.muted,
        borderRadius: material.BorderRadius.circular(radius),
      ),
      child: material.Icon(
        manifest.type == ExtensionType.theme
            ? material.Icons.palette_outlined
            : material.Icons.extension_rounded,
        size: 24,
        color: theme.mutedForeground,
      ),
    );
  }

  material.Widget _buildPreviewBadge(ColorScheme theme) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: material.BoxDecoration(
        color: theme.muted,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(color: theme.border),
      ),
      child: material.Text(
        'Preview',
        style: material.TextStyle(
          fontSize: 11,
          fontWeight: material.FontWeight.w600,
          color: theme.mutedForeground,
        ),
      ),
    );
  }

  material.Widget _buildTagBadge(ColorScheme theme, String tag) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: material.BoxDecoration(
        color: theme.muted,
        borderRadius: material.BorderRadius.circular(4),
      ),
      child: material.Text(
        tag,
        style: material.TextStyle(
          fontSize: 11,
          color: theme.mutedForeground,
          fontWeight: material.FontWeight.w500,
        ),
      ),
    );
  }
}

