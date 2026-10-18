import 'package:flutter/widgets.dart';
import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/core/updater/app_updater_service.dart';
import 'package:querya_desktop/core/updater/sha256_checksums.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';
import 'package:querya_desktop/features/updater/update_changelog_view.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

enum UpdateDialogPhase {
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

/// Shows the update check / download dialog.
Future<void> showUpdateDialog(
  material.BuildContext context, {
  UpdateManifest? initialManifest,
}) {
  return showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(ctx),
      child: UpdateDialogContent(initialManifest: initialManifest),
    ),
  );
}

/// Warns before `exit(0)` when SQL tabs or staged grid edits are dirty.
Future<bool?> showUnsavedUpdateRestartDialog(material.BuildContext context) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) {
      return QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 420),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              const Text('Unsaved changes').semiBold().large(),
              const Gap(8),
              const Text(
                'You have unsaved SQL, staged table edits, or document '
                'changes. Restarting to install the update will discard them.',
              ).muted().small(),
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    QueryaButton.ghost(
                      label: 'Cancel',
                      onPressed: () => material.Navigator.of(ctx).pop(false),
                      size: QueryaControlSize.lg,
                    ),
                    QueryaButton.destructive(
                      label: 'Restart anyway',
                      onPressed: () => material.Navigator.of(ctx).pop(true),
                      size: QueryaControlSize.lg,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The local database could not be copied before the update (#1497): install
/// anyway, or cancel.
Future<bool?> showUpdateBackupFailedDialog(
  material.BuildContext context,
  String error,
) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) {
      return QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 440),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              const Text('Could not back up local data').semiBold().large(),
              const Gap(8),
              Text(
                'Querya Desktop copies its local data (connections, history, '
                'settings) before an update, so you can go back if the new '
                'version changes it. The copy failed: $error',
              ).muted().small(),
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    QueryaButton.ghost(
                      label: 'Cancel',
                      onPressed: () => material.Navigator.of(ctx).pop(false),
                      size: QueryaControlSize.lg,
                    ),
                    QueryaButton.destructive(
                      label: 'Install without a copy',
                      onPressed: () => material.Navigator.of(ctx).pop(true),
                      size: QueryaControlSize.lg,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Update check / download / install pane. Test hooks are optional overrides.
class UpdateDialogContent extends material.StatefulWidget {
  const UpdateDialogContent({
    super.key,
    this.initialManifest,
    this.updater,
    this.controller,
    this.hasUnsavedWork,
    this.isInstallBlocked,
    this.packageUpdateCommand,
    this.selectAsset,
    this.download,
    this.install,
    this.backupLocalData,
    this.confirmRestartIfUnsaved,
    this.showCopyToast = true,
  });

  final UpdateManifest? initialManifest;
  final AppUpdaterService? updater;
  final UpdateController? controller;
  final bool Function()? hasUnsavedWork;
  final bool? isInstallBlocked;
  final String? packageUpdateCommand;
  final UpdateAsset? Function(UpdateManifest manifest)? selectAsset;
  final Future<File> Function(UpdateAsset asset, UpdateManifest manifest)?
      download;
  final Future<void> Function(File file)? install;

  /// Copies the local database before installing; defaults to
  /// [LocalDb.backupBeforeUpdate].
  final Future<void> Function(String fromVersion, String toVersion)?
      backupLocalData;
  final Future<bool?> Function(material.BuildContext context)?
      confirmRestartIfUnsaved;
  final bool showCopyToast;

  @override
  material.State<UpdateDialogContent> createState() =>
      UpdateDialogContentState();
}

@visibleForTesting
class UpdateDialogContentState extends material.State<UpdateDialogContent> {
  late final AppUpdaterService _updater;
  late final UpdateController _controller;

  UpdateDialogPhase _phase = UpdateDialogPhase.checking;
  String _currentVersion = '';
  UpdateManifest? _manifest;
  String? _errorMessage;
  File? _downloadedFile;

  int _receivedBytes = 0;
  int _totalBytes = 0;
  double _bytesPerSecond = 0;
  bool _downloadCancelled = false;
  DateTime? _downloadStarted;
  DateTime? _lastProgressAt;
  int _lastProgressBytes = 0;

  bool get _installBlocked =>
      widget.isInstallBlocked ?? _updater.isInstallBlockedByPackageManager;

  String? get _packageCommand =>
      widget.packageUpdateCommand ?? _updater.packageManagerUpdateCommand;

  @visibleForTesting
  UpdateDialogPhase get phase => _phase;

  @visibleForTesting
  String? get errorMessage => _errorMessage;

  @override
  void initState() {
    super.initState();
    _updater = widget.updater ?? AppUpdaterService.instance;
    _controller = widget.controller ?? UpdateController.instance;
    if (widget.initialManifest != null) {
      _manifest = widget.initialManifest;
      _phase = UpdateDialogPhase.available;
    } else {
      unawaited(_runCheck());
    }
  }

  Future<void> _runCheck() async {
    setState(() {
      _phase = UpdateDialogPhase.checking;
      _errorMessage = null;
    });

    try {
      final result = await _updater.checkForUpdates();
      if (!mounted) return;
      _currentVersion = result.currentVersion;
      if (result.hasUpdate && result.availableUpdate != null) {
        _manifest = result.availableUpdate;
        _controller.setPendingUpdate(_manifest);
        setState(() => _phase = UpdateDialogPhase.available);
      } else {
        setState(() => _phase = UpdateDialogPhase.upToDate);
      }
    } catch (e) {
      _setError(_messageFor(e));
    }
  }

  Future<void> _startDownload() async {
    final manifest = _manifest;
    if (manifest == null) return;
    if (_installBlocked) return;

    final asset = widget.selectAsset?.call(manifest) ??
        _updater.platformAssetFor(manifest);
    if (asset == null) {
      _setError('No update package found for ${Platform.operatingSystem}.');
      return;
    }

    setState(() {
      _phase = UpdateDialogPhase.downloading;
      _downloadCancelled = false;
      _receivedBytes = 0;
      _totalBytes = asset.sizeBytes ?? 0;
      _bytesPerSecond = 0;
      _downloadStarted = DateTime.now();
      _lastProgressAt = _downloadStarted;
      _lastProgressBytes = 0;
      _errorMessage = null;
    });

    try {
      final file = widget.download != null
          ? await widget.download!(asset, manifest)
          : await _updater.downloadAsset(
              asset,
              manifest: manifest,
              shouldCancel: () => _downloadCancelled,
              onProgress: (received, total) {
                if (!mounted) return;
                final now = DateTime.now();
                final elapsedMs =
                    now.difference(_lastProgressAt ?? now).inMilliseconds;
                if (elapsedMs >= 250) {
                  final deltaBytes = received - _lastProgressBytes;
                  _bytesPerSecond = deltaBytes / (elapsedMs / 1000);
                  _lastProgressAt = now;
                  _lastProgressBytes = received;
                }
                setState(() {
                  _receivedBytes = received;
                  if (total > 0) _totalBytes = total;
                });
              },
            );
      if (!mounted) return;
      setState(() {
        _downloadedFile = file;
        _phase = UpdateDialogPhase.readyToInstall;
      });
    } on AppUpdaterException catch (e) {
      if (!mounted) return;
      if (e.message == 'Download cancelled') {
        setState(() => _phase = UpdateDialogPhase.available);
        return;
      }
      _setError(e.message);
    } catch (e) {
      _setError(_messageFor(e));
    }
  }

  Future<void> _install() async {
    final file = _downloadedFile;
    if (file == null) return;

    final dirty = widget.hasUnsavedWork?.call() ??
        UnsavedWorkRegistry.instance.hasUnsaved;
    if (dirty) {
      final confirmFn = widget.confirmRestartIfUnsaved;
      final bool? confirmed;
      if (confirmFn != null) {
        confirmed = await confirmFn(context);
      } else {
        confirmed = await showUnsavedUpdateRestartDialog(context);
      }
      if (!mounted || confirmed != true) return;
    }

    // A copy of the local database first: the new version may change its
    // schema, and an older one cannot read it back (#1497).
    final from = _currentVersion.isEmpty ? 'unknown' : _currentVersion;
    final to = _manifest?.version ?? 'unknown';
    // A test that replaces [install] and not this hook skips the copy.
    final backup = widget.backupLocalData ??
        (widget.install == null
            ? (String f, String t) =>
                LocalDb.instance.backupBeforeUpdate(fromVersion: f, toVersion: t)
            : null);
    try {
      if (backup != null) await backup(from, to);
    } catch (e) {
      if (!mounted) return;
      final proceed = await showUpdateBackupFailedDialog(context, '$e');
      if (!mounted || proceed != true) return;
    }

    try {
      if (widget.install != null) {
        await widget.install!(file);
      } else {
        await _updater.installDownloadedUpdate(file);
      }
    } on AppUpdaterException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(_messageFor(e));
    }
  }

  Future<void> _copyPackageCommand() async {
    final cmd = _packageCommand;
    if (cmd == null || cmd.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: cmd));
    if (!mounted || !widget.showCopyToast) return;
    showAppToast(
      context: context,
      message: 'Copied: $cmd',
      variant: AppToastVariant.success,
    );
  }

  Future<void> _remindLater() async {
    await _controller.remindLater();
    if (mounted) material.Navigator.of(context).pop();
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _phase = UpdateDialogPhase.error;
      _errorMessage = message;
    });
  }

  String _messageFor(Object error) {
    if (error is AppUpdaterException) return error.message;
    if (error is UpdateChecksumMismatchException) {
      return 'The downloaded update failed integrity verification (SHA256 mismatch). '
          'The file was discarded.';
    }
    return error.toString();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String? _releaseDateLabel(DateTime? date) {
    if (date == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  material.Widget build(material.BuildContext context) {
    final colors = context.colors;
    final wb = context.workbench;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 520,
        minWidth: 360,
        maxHeight: 640,
      ),
      borderColor: colors.muted,
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Row(
                  children: [
                    material.Icon(
                      material.Icons.system_update_alt_rounded,
                      color: wb.accent,
                    ),
                    const material.SizedBox(width: 10),
                    const Text('Software Update').large().semiBold(),
                  ],
                ),
                const material.SizedBox(height: 8),
                Text(_subtitle()).muted().small(),
              ],
            ),
          ),
          material.Flexible(
            child: material.SingleChildScrollView(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              child: material.AnimatedSwitcher(
                duration: context.motionDuration(QueryaMotion.standard),
                switchInCurve: context.motionCurve(QueryaMotion.enter),
                switchOutCurve: context.motionCurve(QueryaMotion.exit),
                layoutBuilder: (currentChild, previousChildren) {
                  return material.Stack(
                    alignment: material.Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: material.KeyedSubtree(
                  key: material.ValueKey(_phase),
                  child: _body(context),
                ),
              ),
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
                  color: colors.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: _actions(context),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    return switch (_phase) {
      UpdateDialogPhase.checking => 'Checking for updates…',
      UpdateDialogPhase.upToDate =>
        'You are running the latest version of Querya Desktop (v$_currentVersion).',
      UpdateDialogPhase.available => _installBlocked
          ? 'Querya Desktop v${_manifest?.version ?? ''} is available; '
              'this install is updated outside the app.'
          : 'Querya Desktop v${_manifest?.version ?? ''} is available!',
      UpdateDialogPhase.downloading => 'Downloading update…',
      UpdateDialogPhase.readyToInstall => 'Update ready to install.',
      UpdateDialogPhase.error => 'Update failed.',
    };
  }

  material.Widget _body(material.BuildContext context) {
    return switch (_phase) {
      UpdateDialogPhase.checking => const material.Center(
          child: material.Padding(
            padding: material.EdgeInsets.all(32),
            child: QueryaSpinner(size: QueryaSpinnerSize.lg),
          ),
        ),
      UpdateDialogPhase.upToDate => material.Padding(
          padding: const material.EdgeInsets.symmetric(vertical: 16),
          child: const Text(
            'No newer release was found on the selected update channel.',
          ).muted().small(),
        ),
      UpdateDialogPhase.available ||
      UpdateDialogPhase.downloading ||
      UpdateDialogPhase.readyToInstall =>
        _releaseBody(context),
      UpdateDialogPhase.error => material.Padding(
          padding: const material.EdgeInsets.symmetric(vertical: 16),
          child: Text(_errorMessage ?? 'Unknown error').small(),
        ),
    };
  }

  material.Widget _releaseBody(material.BuildContext context) {
    final manifest = _manifest;
    if (manifest == null) return const material.SizedBox.shrink();

    final dateLabel = _releaseDateLabel(manifest.releaseDate);
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        if (_installBlocked && _phase == UpdateDialogPhase.available) ...[
          Text(
            _packageCommand != null
                ? 'Install updates with $_packageCommand '
                    'instead of downloading a GitHub package.'
                : _updater.packageManagerUpdateHint,
          ).muted().small(),
          const material.SizedBox(height: 12),
        ],
        if (dateLabel != null) ...[
          Text('Released $dateLabel').muted().xSmall(),
          const material.SizedBox(height: 12),
        ],
        if (_phase == UpdateDialogPhase.downloading) ...[
          material.LinearProgressIndicator(
            value: _totalBytes > 0 ? _receivedBytes / _totalBytes : null,
          ),
          const material.SizedBox(height: 8),
          Text(
            '${_formatBytes(_receivedBytes)}'
            '${_totalBytes > 0 ? ' / ${_formatBytes(_totalBytes)}' : ''}'
            '${_bytesPerSecond > 0 ? ' · ${_formatBytes(_bytesPerSecond.round())}/s' : ''}',
          ).muted().xSmall(),
          const material.SizedBox(height: 16),
        ],
        if (manifest.changelog.isNotEmpty) ...[
          const Text('Release notes').semiBold().small(),
          const material.SizedBox(height: 8),
          material.Container(
            constraints: const material.BoxConstraints(maxHeight: 280),
            padding: const material.EdgeInsets.all(12),
            decoration: material.BoxDecoration(
              color: context.workbench.surface.withValues(alpha: 0.55),
              borderRadius: material.BorderRadius.circular(8),
              border: material.Border.all(
                color: context.workbench.borderSubtle.withValues(alpha: 0.6),
              ),
            ),
            child: material.SingleChildScrollView(
              child: UpdateChangelogView(markdown: manifest.changelog),
            ),
          ),
        ],
      ],
    );
  }

  material.Widget _actions(material.BuildContext context) {
    return material.Row(
      mainAxisAlignment: material.MainAxisAlignment.end,
      children: [
        ...switch (_phase) {
          UpdateDialogPhase.checking => [
              QueryaButton.ghost(
                label: 'Close',
                onPressed: () => material.Navigator.of(context).pop(),
                size: QueryaControlSize.lg,
              ),
            ],
          UpdateDialogPhase.upToDate => [
              QueryaButton.ghost(
                label: 'Close',
                onPressed: () => material.Navigator.of(context).pop(),
                size: QueryaControlSize.lg,
              ),
            ],
          UpdateDialogPhase.available => [
              QueryaButton.ghost(
                label: 'Remind me later',
                onPressed: () => unawaited(_remindLater()),
                size: QueryaControlSize.lg,
              ),
              const material.SizedBox(width: 8),
              if (_installBlocked && _packageCommand != null)
                QueryaButton.primary(
                  label: 'Copy update command',
                  onPressed: () => unawaited(_copyPackageCommand()),
                  size: QueryaControlSize.lg,
                )
              else if (_installBlocked)
                QueryaButton.primary(
                  label: 'Open release page',
                  onPressed: () => unawaited(launchUrlString(
                    'https://github.com/QueryaHub/Querya-Desktop/releases/tag/'
                    '${_manifest?.version ?? ''}',
                    mode: LaunchMode.externalApplication,
                  )),
                  size: QueryaControlSize.lg,
                )
              else
                QueryaButton.primary(
                  label: 'Download',
                  onPressed: () => unawaited(_startDownload()),
                  size: QueryaControlSize.lg,
                ),
            ],
          UpdateDialogPhase.downloading => [
              QueryaButton.ghost(
                label: 'Cancel',
                onPressed: () {
                  setState(() => _downloadCancelled = true);
                },
                size: QueryaControlSize.lg,
              ),
            ],
          UpdateDialogPhase.readyToInstall => [
              QueryaButton.ghost(
                label: 'Close',
                onPressed: () => material.Navigator.of(context).pop(),
                size: QueryaControlSize.lg,
              ),
              const material.SizedBox(width: 8),
              QueryaButton.primary(
                label: 'Restart & Update Now',
                onPressed: () => unawaited(_install()),
                size: QueryaControlSize.lg,
              ),
            ],
          UpdateDialogPhase.error => [
              QueryaButton.ghost(
                label: 'Close',
                onPressed: () => material.Navigator.of(context).pop(),
                size: QueryaControlSize.lg,
              ),
              const material.SizedBox(width: 8),
              QueryaButton.primary(
                label: 'Retry',
                onPressed: () => unawaited(_runCheck()),
                size: QueryaControlSize.lg,
              ),
            ],
        },
      ],
    );
  }
}
