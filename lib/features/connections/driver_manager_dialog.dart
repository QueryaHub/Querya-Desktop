import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/drivers/driver_storage.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'new_connection_dialog.dart';

/// Driver status shown in Driver Manager.
enum DriverStatus {
  available,
  installed,
  comingSoon,
}

/// One row in the driver list: [type] for icon/label, [description], optional [downloadable] for install state.
typedef _DriverInfo = ({
  ConnectionType type,
  String description,
  DriverStatus? fixedStatus,
  DownloadableDriver? downloadable,
});

final _driverInfoList = <_DriverInfo>[
  (type: ConnectionType.postgresql, description: 'PostgreSQL server connection (JDBC driver)', fixedStatus: null, downloadable: DownloadableDriver.postgresql),
  (type: ConnectionType.mysql, description: 'MySQL / MariaDB server connection', fixedStatus: DriverStatus.installed, downloadable: null),
  (type: ConnectionType.redis, description: 'Redis server connection', fixedStatus: DriverStatus.installed, downloadable: null),
  (type: ConnectionType.mongodb, description: 'MongoDB server connection', fixedStatus: DriverStatus.installed, downloadable: null),
];

/// Shows the Driver Manager dialog: list of built-in database drivers and their status.
void showDriverManagerDialog(BuildContext context) {
  showAppDialog<void>(
    context: context,
    builder: (context) => const material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: material.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: _DriverManagerDialogContent(),
    ),
  );
}

class _DriverManagerDialogContent extends material.StatefulWidget {
  const _DriverManagerDialogContent();

  @override
  material.State<_DriverManagerDialogContent> createState() => _DriverManagerDialogContentState();
}

class _DriverManagerDialogContentState extends material.State<_DriverManagerDialogContent> {
  final Map<DownloadableDriver, bool?> _installed = {};
  DownloadableDriver? _loadingDriver;
  final Map<DownloadableDriver, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    _refreshAllStatuses();
  }

  Future<void> _refreshAllStatuses() async {
    for (final d in DownloadableDriver.values) {
      final installed = await DriverStorage.instance.isInstalled(d);
      if (mounted) setState(() => _installed[d] = installed);
    }
  }

  Future<void> _download(DownloadableDriver driver) async {
    setState(() {
      _errors.remove(driver);
      _loadingDriver = driver;
    });
    try {
      await DriverStorage.instance.download(driver);
      if (mounted) setState(() => _installed[driver] = true);
    } on DriverDownloadException catch (e) {
      if (mounted) setState(() => _errors[driver] = e.message);
    } catch (e) {
      if (mounted) setState(() => _errors[driver] = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDriver = null);
    }
  }

  Future<void> _delete(DownloadableDriver driver) async {
    setState(() => _loadingDriver = driver);
    try {
      await DriverStorage.instance.delete(driver);
      if (mounted) setState(() => _installed[driver] = false);
    } finally {
      if (mounted) setState(() => _loadingDriver = null);
    }
  }

  DriverStatus _statusFor(_DriverInfo info) {
    if (info.fixedStatus != null) return info.fixedStatus!;
    final driver = info.downloadable!;
    final installed = _installed[driver];
    if (installed == null) return DriverStatus.comingSoon;
    return installed ? DriverStatus.installed : DriverStatus.available;
  }

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
                    'Built-in database drivers. Add new connection types via Connection → New Database Connection.',
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
                    final status = _statusFor(info);
                    final driver = info.downloadable;
                    final loading = driver != null && _loadingDriver == driver;
                    final error = driver != null ? _errors[driver] : null;
                    return _DriverRow(
                      type: info.type,
                      status: status,
                      description: info.description,
                      theme: theme,
                      isBuiltIn: info.downloadable == null && status == DriverStatus.installed,
                      loading: loading,
                      error: error,
                      onDownload: driver != null ? () => _download(driver) : null,
                      onUninstall: driver != null ? () => _delete(driver) : null,
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
    required this.status,
    required this.description,
    required this.theme,
    this.isBuiltIn = false,
    this.loading = false,
    this.error,
    this.onDownload,
    this.onUninstall,
  });

  final ConnectionType type;
  final DriverStatus status;
  final String description;
  final ColorScheme theme;
  final bool isBuiltIn;
  final bool loading;
  final String? error;
  final VoidCallback? onDownload;
  final VoidCallback? onUninstall;

  @override
  material.Widget build(material.BuildContext context) {
    final showDownload = !isBuiltIn && status == DriverStatus.available && onDownload != null;
    final showUninstall = !isBuiltIn && status == DriverStatus.installed && onUninstall != null;
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
                if (error != null) ...[
                  const material.SizedBox(height: 4),
                  Text(
                    error!,
                    style: material.TextStyle(
                      fontSize: 11,
                      color: theme.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isBuiltIn) ...[
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
          ] else if (showDownload || showUninstall) ...[
            const material.SizedBox(width: 8),
            if (showDownload)
              loading
                  ? material.SizedBox(
                      width: 32,
                      height: 32,
                      child: material.Center(
                        child: material.SizedBox(
                          width: 20,
                          height: 20,
                          child: material.CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.primary,
                          ),
                        ),
                      ),
                    )
                  : IconButton.ghost(
                      onPressed: onDownload,
                      icon: material.Icon(
                        material.Icons.download_rounded,
                        size: 20,
                        color: theme.primary,
                      ),
                    ),
            if (showUninstall)
              loading
                  ? material.SizedBox(
                      width: 32,
                      height: 32,
                      child: material.Center(
                        child: material.SizedBox(
                          width: 20,
                          height: 20,
                          child: material.CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.primary,
                          ),
                        ),
                      ),
                    )
                  : IconButton.destructive(
                      onPressed: onUninstall,
                      icon: const material.Icon(
                        material.Icons.delete_outline_rounded,
                        size: 20,
                      ),
                    ),
          ],
        ],
      ),
    );
  }
}
