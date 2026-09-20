import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/core/updater/app_updater_service.dart';
import 'package:querya_desktop/core/updater/sha256_checksums.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';
import 'package:querya_desktop/features/updater/update_changelog_view.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

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
                'You have unsaved SQL or staged table changes. '
                'Restarting to install the update will discard them.',
              ).muted().small(),
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlineButton(
                      onPressed: () => material.Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    DestructiveButton(
                      onPressed: () => material.Navigator.of(ctx).pop(true),
                      child: const Text('Restart anyway'),
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
    final theme = Theme.of(context).colorScheme;
    final wb = context.workbench;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 520,
        minWidth: 360,
        maxHeight: 640,
      ),
      borderColor: theme.muted,
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
                  color: theme.border.withValues(alpha: 0.3),
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
          ? 'This build is managed by ${_packageCommand ?? 'the package manager'}.'
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
            child: material.CircularProgressIndicator(),
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
            'Install updates with ${_packageCommand ?? 'the system package manager'} '
            'instead of downloading a GitHub package.',
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
              GhostButton(
                onPressed: () => material.Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          UpdateDialogPhase.upToDate => [
              PrimaryButton(
                onPressed: () => material.Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          UpdateDialogPhase.available => [
              GhostButton(
                onPressed: () => unawaited(_remindLater()),
                child: const Text('Remind me later'),
              ),
              const material.SizedBox(width: 8),
              if (_installBlocked)
                PrimaryButton(
                  onPressed: () => unawaited(_copyPackageCommand()),
                  child: const Text('Copy update command'),
                )
              else
                PrimaryButton(
                  onPressed: () => unawaited(_startDownload()),
                  child: const Text('Download'),
                ),
            ],
          UpdateDialogPhase.downloading => [
              GhostButton(
                onPressed: () {
                  setState(() => _downloadCancelled = true);
                },
                child: const Text('Cancel'),
              ),
            ],
          UpdateDialogPhase.readyToInstall => [
              GhostButton(
                onPressed: () => material.Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              const material.SizedBox(width: 8),
              PrimaryButton(
                onPressed: () => unawaited(_install()),
                child: const Text('Restart & Update Now'),
              ),
            ],
          UpdateDialogPhase.error => [
              GhostButton(
                onPressed: () => material.Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              const material.SizedBox(width: 8),
              PrimaryButton(
                onPressed: () => unawaited(_runCheck()),
                child: const Text('Retry'),
              ),
            ],
        },
      ],
    );
  }
}
