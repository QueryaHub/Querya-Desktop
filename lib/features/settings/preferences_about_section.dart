import 'package:flutter/material.dart' as material;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/platform/open_directory.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/theme/theme_paths.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

class PreferencesAboutSection extends material.StatefulWidget {
  const PreferencesAboutSection({super.key});

  static const String githubRepoUrl =
      'https://github.com/QueryaHub/Querya-Desktop';

  @override
  material.State<PreferencesAboutSection> createState() =>
      _PreferencesAboutSectionState();
}

class _PreferencesAboutSectionState
    extends material.State<PreferencesAboutSection> {
  // Created once: a future made in build() would restart on every rebuild of
  // the dialog (every keystroke in its search) and make these rows flicker.
  late final Future<String> _version = PackageInfo.fromPlatform()
      .then((i) => i.version)
      .catchError((Object _) => '');
  late final Future<bool> _portable = AppDataRoot.isPortableMode();

  static const githubRepoUrl = PreferencesAboutSection.githubRepoUrl;

  @override
  Widget build(BuildContext context) {

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        // App Header Card
        material.Container(
          padding: const material.EdgeInsets.all(16),
          decoration: material.BoxDecoration(
            color: context.colors.muted.withValues(alpha: 0.18),
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(
              color: context.colors.border.withValues(alpha: 0.25),
            ),
          ),
          child: material.Row(
            children: [
              material.Container(
                width: 48,
                height: 48,
                decoration: material.BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  borderRadius: material.BorderRadius.circular(8),
                  border: material.Border.all(
                    color: context.colors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: material.Center(
                  child: material.Image.asset(
                    'assets/images/querya_logo.png',
                    width: 28,
                    height: 28,
                    filterQuality: material.FilterQuality.medium,
                    errorBuilder: (_, __, ___) => material.Icon(
                      QueryaIcons.database,
                      size: 24,
                      color: context.colors.primary,
                    ),
                  ),
                ),
              ),
              const material.SizedBox(width: 16),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    const Text('Querya Desktop')
                        .semiBold()
                        .large()
                        .foreground(),
                    const material.SizedBox(height: 2),
                    FutureBuilder<String>(
                      future: _version,
                      builder: (context, snapshot) => Text(
                        snapshot.data?.isNotEmpty == true
                            ? 'Version ${snapshot.data} (Desktop Build)'
                            : 'Desktop Build',
                      ).muted().small(),
                    ),
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

        FutureBuilder<bool>(
          future: _portable,
          builder: (context, snapshot) {
            final isPortable = snapshot.data ?? false;
            if (!isPortable) return const SizedBox.shrink();
            return material.Container(
              margin: const material.EdgeInsets.only(bottom: 12),
              padding: const material.EdgeInsets.all(12),
              decoration: material.BoxDecoration(
                color: context.colors.muted.withValues(alpha: 0.25),
                borderRadius: material.BorderRadius.circular(6),
                border: material.Border.all(
                  color: context.colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const QueryaBadge.status(
                    'PORTABLE',
                    status: QueryaBadgeStatus.info,
                  ),
                  const material.SizedBox(width: 10),
                  material.Expanded(
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        const Text('Portable Mode Active')
                            .semiBold()
                            .small()
                            .foreground(),
                        const material.SizedBox(height: 2),
                        const Text(
                          'Data, settings, and themes are stored in the local QueryaData folder. Connection passwords remain protected in the host OS keyring.',
                        ).muted().xSmall(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            QueryaButton.secondary(
              label: 'Open app data folder',
              icon: material.Icons.folder_outlined,
              onPressed: () async {
                final dir = await AppDataRoot.applicationSupportDirectory();
                await openDirectoryInFileManager(dir.path);
              },
              size: QueryaControlSize.md,
            ),
            QueryaButton.secondary(
              label: 'Open themes folder',
              icon: material.Icons.palette_outlined,
              onPressed: () async {
                final dir = await ThemePaths.ensureUserThemesDirectory();
                await openDirectoryInFileManager(dir.path);
              },
              size: QueryaControlSize.md,
            ),
            QueryaButton.secondary(
              label: 'Open extensions folder',
              icon: material.Icons.extension_outlined,
              onPressed: () async {
                final dir = await ExtensionPaths.ensureExtensionsDirectory();
                await openDirectoryInFileManager(dir.path);
              },
              size: QueryaControlSize.md,
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
            QueryaButton.secondary(
              label: 'GitHub repository',
              icon: material.Icons.code_rounded,
              onPressed: () => launchUrlString(
                githubRepoUrl,
                mode: LaunchMode.externalApplication,
              ),
              size: QueryaControlSize.md,
            ),
            QueryaButton.secondary(
              label: 'Report an issue',
              icon: material.Icons.bug_report_outlined,
              onPressed: () => launchUrlString(
                '$githubRepoUrl/issues',
                mode: LaunchMode.externalApplication,
              ),
              size: QueryaControlSize.md,
            ),
          ],
        ),
      ],
    );
  }
}
