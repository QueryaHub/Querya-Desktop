import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/platform/open_directory.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/theme/theme_paths.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PreferencesAboutSection extends StatelessWidget {
  const PreferencesAboutSection({super.key});

  static const String appVersion = '0.4.15';
  static const String githubRepoUrl = 'https://github.com/QueryaHub/Querya-Desktop';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        // App Header Card
        material.Container(
          padding: const material.EdgeInsets.all(16),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.18),
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(
              color: theme.colorScheme.border.withValues(alpha: 0.25),
            ),
          ),
          child: material.Row(
            children: [
              material.Container(
                width: 48,
                height: 48,
                decoration: material.BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: material.BorderRadius.circular(8),
                  border: material.Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: material.Center(
                  child: material.Icon(
                    QueryaIcons.database,
                    size: 24,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const material.SizedBox(width: 16),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    const Text('Querya Desktop').semiBold().large().foreground(),
                    const material.SizedBox(height: 2),
                    const Text('Version $appVersion (Desktop Build)').muted().small(),
                    const material.SizedBox(height: 4),
                    const Text('Fast, native multi-database management studio.')
                        .muted()
                        .xSmall(),
                  ],
                ),
              ),
            ],
          ),
        ),

        const material.SizedBox(height: 20),
        const Text('Storage & Directories').semiBold().small().foreground(),
        const material.SizedBox(height: 6),
        const Text(
          'Querya stores connection credentials securely and configuration in local SQLite.',
        ).muted().xSmall(),
        const material.SizedBox(height: 12),

        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed: () async {
                final dir = await AppDataRoot.applicationSupportDirectory();
                await openDirectoryInFileManager(dir.path);
              },
              child: const material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.Icon(material.Icons.folder_outlined, size: 14),
                  material.SizedBox(width: 6),
                  material.Text('Open App Data Folder'),
                ],
              ),
            ),
            OutlineButton(
              onPressed: () async {
                final dir = await ThemePaths.ensureUserThemesDirectory();
                await openDirectoryInFileManager(dir.path);
              },
              child: const material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.Icon(material.Icons.palette_outlined, size: 14),
                  material.SizedBox(width: 6),
                  material.Text('Open Themes Folder'),
                ],
              ),
            ),
            OutlineButton(
              onPressed: () async {
                final dir = await ExtensionPaths.ensureExtensionsDirectory();
                await openDirectoryInFileManager(dir.path);
              },
              child: const material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.Icon(material.Icons.extension_outlined, size: 14),
                  material.SizedBox(width: 6),
                  material.Text('Open Extensions Folder'),
                ],
              ),
            ),
          ],
        ),

        const material.SizedBox(height: 24),
        const Text('Community & Support').semiBold().small().foreground(),
        const material.SizedBox(height: 12),

        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed: () => launchUrlString(
                githubRepoUrl,
                mode: LaunchMode.externalApplication,
              ),
              child: const material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.Icon(material.Icons.code_rounded, size: 14),
                  material.SizedBox(width: 6),
                  material.Text('GitHub Repository'),
                ],
              ),
            ),
            OutlineButton(
              onPressed: () => launchUrlString(
                '$githubRepoUrl/issues',
                mode: LaunchMode.externalApplication,
              ),
              child: const material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  material.Icon(material.Icons.bug_report_outlined, size: 14),
                  material.SizedBox(width: 6),
                  material.Text('Report an Issue'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
