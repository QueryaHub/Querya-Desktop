import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/features/connections/connection_type_choice.dart';
import 'package:querya_desktop/features/connections/driver_icon.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// One row in the driver list.
typedef _DriverInfo = ({
  String label,
  material.IconData icon,
  String? iconAsset,
  String? iconFile,
  String description,
  String badge,
});

/// Shows built-in and installed extension database drivers.
Future<void> showDriverManagerDialog(material.BuildContext context) async {
  await LocalExtensionRegistry.instance.load();
  if (!context.mounted) return;
  return showAppDialog<void>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: const _DriverManagerDialogContent(),
    ),
  );
}

List<_DriverInfo> _buildDriverList() {
  final list = <_DriverInfo>[
    for (final choice in ExtensionDriverCatalog.builtInChoices)
      if (choice is BuiltInConnectionType)
        (
          label: choice.label,
          icon: choice.icon,
          iconAsset: choice.iconAsset,
          iconFile: null,
          description: switch (choice.type) {
            ConnectionType.postgresql =>
              'PostgreSQL — built-in Dart driver (`postgres`).',
            ConnectionType.mysql =>
              'MySQL / MariaDB — built-in Dart driver (`mysql_client`).',
            ConnectionType.sqlite =>
              'SQLite — built-in Dart driver (`sqflite_common_ffi`).',
            ConnectionType.redis => 'Redis — built-in Dart client (`redis`).',
            ConnectionType.mongodb =>
              'MongoDB — built-in Dart driver (`mongo_dart`).',
          },
          badge: 'Built-in',
        ),
  ];

  for (final choice in ExtensionDriverCatalog.extensionChoices()) {
    list.add((
      label: choice.label,
      icon: choice.icon,
      iconAsset: null,
      iconFile: choice.iconFile,
      description:
          'Extension · ${choice.manifest.id} · driverId=${choice.driver.driverId}',
      badge: 'Extension',
    ));
  }
  return list;
}

class _DriverManagerDialogContent extends material.StatelessWidget {
  const _DriverManagerDialogContent();

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    final drivers = _buildDriverList();
    return material.Container(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 520,
        minWidth: 400,
      ),
      decoration: material.BoxDecoration(
        color: theme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: theme.muted),
      ),
      child: material.ClipRRect(
        borderRadius: material.BorderRadius.circular(radius),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Driver Manager').large().semiBold(),
                  const material.SizedBox(height: 6),
                  const Text(
                    'Built-in Dart drivers and installed sandboxed extension drivers. '
                    'Add a server under Connection → New Database Connection.',
                  ).muted().small(),
                ],
              ),
            ),
            material.Padding(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              child: material.Container(
                decoration: material.BoxDecoration(
                  color: theme.muted.withValues(alpha: 0.15),
                  borderRadius: material.BorderRadius.circular(10),
                  border: material.Border.all(
                      color: theme.border.withValues(alpha: 0.3)),
                ),
                child: material.ListView.separated(
                  shrinkWrap: true,
                  padding: const material.EdgeInsets.symmetric(vertical: 8),
                  itemCount: drivers.length,
                  separatorBuilder: (_, __) => material.Divider(
                    height: 1,
                    color: theme.border.withValues(alpha: 0.3),
                  ),
                  itemBuilder: (context, index) {
                    final info = drivers[index];
                    return _DriverRow(info: info, theme: theme);
                  },
                ),
              ),
            ),
            material.Container(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              decoration: material.BoxDecoration(
                border: material.Border(
                  top: material.BorderSide(
                      color: theme.border.withValues(alpha: 0.3)),
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
      ),
    );
  }
}

class _DriverRow extends material.StatelessWidget {
  const _DriverRow({
    required this.info,
    required this.theme,
  });

  final _DriverInfo info;
  final ColorScheme theme;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding:
          const material.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.center,
        children: [
          material.SizedBox(
            width: 40,
            height: 40,
            child: DriverIcon(
              filePath: info.iconFile,
              assetPath: info.iconAsset,
              size: 40,
              fallbackIcon: info.icon,
            ),
          ),
          const material.SizedBox(width: 16),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                Text(info.label).semiBold().small(),
                const material.SizedBox(height: 2),
                Text(info.description).muted().xSmall(),
              ],
            ),
          ),
          const material.SizedBox(width: 8),
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: material.BoxDecoration(
              color: theme.primary.withValues(alpha: 0.12),
              borderRadius: material.BorderRadius.circular(6),
              border: material.Border.all(
                color: theme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              info.badge,
              style: material.TextStyle(
                fontSize: 11,
                fontWeight: material.FontWeight.w600,
                color: theme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
