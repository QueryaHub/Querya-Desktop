import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'new_connection_dialog.dart';

/// One row in the driver list.
typedef _DriverInfo = ({
  ConnectionType type,
  String description,
});

/// Built-in drivers (Dart packages). No separate JDBC/JAR install is required to connect.
final _driverInfoList = <_DriverInfo>[
  (
    type: ConnectionType.postgresql,
    description:
        'PostgreSQL — built-in Dart driver (`postgres`). Use Connection → New Database Connection.',
  ),
  (
    type: ConnectionType.mysql,
    description: 'MySQL / MariaDB — built-in Dart driver (`mysql_client`).',
  ),
  (
    type: ConnectionType.redis,
    description: 'Redis — built-in Dart client (`redis`).',
  ),
  (
    type: ConnectionType.mongodb,
    description: 'MongoDB — built-in Dart driver (`mongo_dart`).',
  ),
];

/// Shows built-in database drivers shipped with the app.
void showDriverManagerDialog(BuildContext context) {
  showAppDialog<void>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: const _DriverManagerDialogContent(),
    ),
  );
}

class _DriverManagerDialogContent extends material.StatelessWidget {
  const _DriverManagerDialogContent();

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Container(
      constraints: const material.BoxConstraints(maxWidth: 520, minWidth: 400),
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
                    'Querya connects using built-in Dart drivers. Add a server under Connection → New Database Connection.',
                  ).muted().small(),
                ],
              ),
            ),
            material.Padding(
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: material.Container(
                decoration: material.BoxDecoration(
                  color: theme.muted.withValues(alpha: 0.15),
                  borderRadius: material.BorderRadius.circular(10),
                  border: material.Border.all(color: theme.border.withValues(alpha: 0.3)),
                ),
                child: material.ListView.separated(
                  shrinkWrap: true,
                  padding: const material.EdgeInsets.symmetric(vertical: 8),
                  itemCount: _driverInfoList.length,
                  separatorBuilder: (_, __) => material.Divider(
                    height: 1,
                    color: theme.border.withValues(alpha: 0.3),
                  ),
                  itemBuilder: (context, index) {
                    final info = _driverInfoList[index];
                    return _DriverRow(
                      type: info.type,
                      description: info.description,
                      theme: theme,
                    );
                  },
                ),
              ),
            ),
            material.Container(
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: material.BoxDecoration(
                border: material.Border(
                  top: material.BorderSide(color: theme.border.withValues(alpha: 0.3)),
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
    required this.type,
    required this.description,
    required this.theme,
  });

  final ConnectionType type;
  final String description;
  final ColorScheme theme;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.center,
        children: [
          material.SizedBox(
            width: 40,
            height: 40,
            child: type.iconAsset != null
                ? material.Image.asset(
                    type.iconAsset!,
                    fit: material.BoxFit.contain,
                    filterQuality: material.FilterQuality.medium,
                  )
                : material.Icon(type.icon, size: 40, color: theme.primary),
          ),
          const material.SizedBox(width: 16),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                Text(type.label).semiBold().small(),
                const material.SizedBox(height: 2),
                Text(description).muted().xSmall(),
              ],
            ),
          ),
          const material.SizedBox(width: 8),
          material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: material.BoxDecoration(
              color: theme.primary.withValues(alpha: 0.12),
              borderRadius: material.BorderRadius.circular(6),
              border: material.Border.all(
                color: theme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              'Built-in',
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
