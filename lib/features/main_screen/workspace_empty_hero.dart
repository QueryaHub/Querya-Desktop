import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Task-oriented empty workspace shown before a connection is selected.
class WorkspaceEmptyHero extends StatelessWidget {
  const WorkspaceEmptyHero({
    super.key,
    required this.onNewConnection,
    this.onNewConnectionFromUrl,
    this.onOpenSqlite,
  });

  final VoidCallback onNewConnection;
  final VoidCallback? onNewConnectionFromUrl;
  final VoidCallback? onOpenSqlite;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wb = context.workbench;

    return material.LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < WindowLayout.compactWindowWidth;
        final horizontal =
            WindowLayout.heroHorizontalPadding(constraints.maxWidth);

        return material.SingleChildScrollView(
          padding: material.EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: compact ? 24 : 48,
          ),
          child: material.Align(
            alignment: material.Alignment.topCenter,
            child: material.ConstrainedBox(
              constraints: const material.BoxConstraints(maxWidth: 720),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Icon(
                    material.Icons.storage_rounded,
                    size: compact ? 38 : 46,
                    color: cs.primary,
                  ),
                  material.SizedBox(height: compact ? 14 : 18),
                  material.Text(
                    'Start working with your data',
                    textAlign: material.TextAlign.center,
                    style: material.TextStyle(
                      color: cs.foreground,
                      fontSize: compact ? 22 : 28,
                      fontWeight: material.FontWeight.w600,
                    ),
                  ),
                  const material.SizedBox(height: 8),
                  material.Text(
                    'Connect to a database or open a local SQLite file.',
                    textAlign: material.TextAlign.center,
                    style: material.TextStyle(
                      color: cs.mutedForeground,
                      fontSize: compact ? 13 : 14,
                    ),
                  ),
                  material.SizedBox(height: compact ? 24 : 32),
                  material.Wrap(
                    alignment: material.WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      PrimaryButton(
                        key: const Key('empty_new_connection'),
                        onPressed: onNewConnection,
                        leading: const material.Icon(
                          material.Icons.add_link_rounded,
                          size: 18,
                        ),
                        child: const Text('New connection'),
                      ),
                      if (onNewConnectionFromUrl != null)
                        OutlineButton(
                          key: const Key('empty_new_from_url'),
                          onPressed: onNewConnectionFromUrl,
                          leading: const material.Icon(
                            material.Icons.link_rounded,
                            size: 18,
                          ),
                          child: const Text('New from URL'),
                        ),
                      if (onOpenSqlite != null)
                        OutlineButton(
                          key: const Key('empty_open_sqlite'),
                          onPressed: onOpenSqlite,
                          leading: const material.Icon(
                            material.Icons.folder_open_rounded,
                            size: 18,
                          ),
                          child: const Text('Open SQLite file'),
                        ),
                    ],
                  ),
                  material.SizedBox(height: compact ? 28 : 40),
                  material.Container(
                    padding: material.EdgeInsets.all(compact ? 16 : 20),
                    decoration: material.BoxDecoration(
                      color: wb.surface,
                      borderRadius: material.BorderRadius.circular(12),
                      border: material.Border.all(
                        color: wb.borderSubtle.withValues(alpha: 0.55),
                      ),
                    ),
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        material.Text(
                          'Quick start',
                          style: material.TextStyle(
                            color: cs.foreground,
                            fontSize: 14,
                            fontWeight: material.FontWeight.w600,
                          ),
                        ),
                        const material.SizedBox(height: 12),
                        _QuickStartRow(
                          icon: material.Icons.dns_rounded,
                          title: 'Server databases',
                          description:
                              'PostgreSQL, MySQL, MongoDB, Redis and extension drivers',
                          color: cs.primary,
                        ),
                        const material.SizedBox(height: 12),
                        _QuickStartRow(
                          icon: material.Icons.insert_drive_file_rounded,
                          title: 'Local database',
                          description:
                              'Open an existing SQLite file or create a connection',
                          color: cs.primary,
                        ),
                        const material.SizedBox(height: 12),
                        _QuickStartRow(
                          icon: material.Icons.security_rounded,
                          title: 'Credentials stay protected',
                          description:
                              'Passwords are stored in your operating system secure store',
                          color: cs.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final material.IconData icon;
  final String title;
  final String description;
  final material.Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.Row(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Icon(icon, size: 18, color: color),
        const material.SizedBox(width: 12),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              material.Text(
                title,
                style: material.TextStyle(
                  color: cs.foreground,
                  fontSize: 13,
                  fontWeight: material.FontWeight.w500,
                ),
              ),
              const material.SizedBox(height: 2),
              material.Text(
                description,
                style: material.TextStyle(
                  color: cs.mutedForeground,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
