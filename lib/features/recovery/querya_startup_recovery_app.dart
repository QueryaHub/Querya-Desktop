import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/app/app.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Disaster recovery UI launched when LocalDb fails to open or migrate on startup.
/// Allows the user to inspect the error, retry, remove stale locks, backup the database,
/// or launch in Safe Mode.
class QueryaStartupRecoveryApp extends material.StatefulWidget {
  const QueryaStartupRecoveryApp({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetrySuccess,
  });

  final Object error;
  final StackTrace? stackTrace;
  final material.VoidCallback? onRetrySuccess;

  @override
  material.State<QueryaStartupRecoveryApp> createState() =>
      _QueryaStartupRecoveryAppState();
}

class _QueryaStartupRecoveryAppState
    extends material.State<QueryaStartupRecoveryApp> {
  bool _isBusy = false;
  String? _statusMessage;
  bool _isErrorStatus = false;

  void _setStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _isErrorStatus = isError;
    });
  }

  Future<void> _handleRetry() async {
    setState(() => _isBusy = true);
    _setStatus('Attempting to open database...');
    try {
      await LocalDb.instance.open();
      _setStatus('Database opened successfully!');
      if (mounted) {
        if (widget.onRetrySuccess != null) {
          widget.onRetrySuccess!();
        } else {
          material.runApp(const QueryaApp());
        }
      }
    } catch (e) {
      _setStatus('Retry failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleUnlockWal() async {
    setState(() => _isBusy = true);
    _setStatus('Removing WAL and lock files...');
    try {
      await LocalDb.instance.removeWalAndLockFiles();
      _setStatus('Stale lock and WAL files removed. Testing database connection...');
      await LocalDb.instance.open();
      _setStatus('Database opened successfully!');
      if (mounted) {
        if (widget.onRetrySuccess != null) {
          widget.onRetrySuccess!();
        } else {
          material.runApp(const QueryaApp());
        }
      }
    } catch (e) {
      _setStatus('Unlock attempted, but database failed to open: $e',
          isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleBackup() async {
    setState(() => _isBusy = true);
    _setStatus('Creating timestamped backup...');
    try {
      final backupPath = await LocalDb.instance.backupDatabaseFile();
      _setStatus('Backup saved to: $backupPath');
    } catch (e) {
      _setStatus('Backup failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleSafeMode() async {
    setState(() => _isBusy = true);
    _setStatus('Switching to clean safe profile...');
    try {
      await LocalDb.instance.close();
      final tempDir = await Directory.systemTemp.createTemp('querya_safe_mode_');
      AppDataRoot.setSafeModeRootPath(tempDir.path);
      await LocalDb.instance.open();
      _setStatus('Safe mode ready. Launching Querya...');
      if (mounted) {
        if (widget.onRetrySuccess != null) {
          widget.onRetrySuccess!();
        } else {
          material.runApp(const QueryaApp());
        }
      }
    } catch (e) {
      _setStatus('Failed to enter safe mode: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final themeData = ThemeController.instance.darkShadcnTheme;
    final colorScheme = themeData.colorScheme;

    return ShadcnApp(
      title: 'Querya - Startup Recovery',
      theme: ThemeController.instance.darkShadcnTheme,
      darkTheme: ThemeController.instance.darkShadcnTheme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: material.Scaffold(
        backgroundColor: colorScheme.background,
        body: material.Center(
          child: material.SingleChildScrollView(
            padding: const material.EdgeInsets.all(32),
            child: material.ConstrainedBox(
              constraints: const material.BoxConstraints(maxWidth: 640),
              child: QueryaDialogCard(
                borderColor: colorScheme.destructive,
                child: material.Padding(
                  padding: const material.EdgeInsets.all(28),
                  child: material.Column(
                    mainAxisSize: material.MainAxisSize.min,
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      material.Row(
                        children: [
                          material.Icon(
                            QueryaIcons.treeError,
                            size: 32,
                            color: colorScheme.destructive,
                          ),
                          const material.SizedBox(width: 12),
                          const material.Expanded(
                            child: Text(
                              'Database Recovery',
                            ),
                          ),
                        ],
                      ),
                      const material.SizedBox(height: 16),
                      const Text(
                        'Querya could not open the profile database (querya.db) on startup. '
                        'This can happen after a crash, concurrent lock, file permission conflict, '
                        'or SQLite database corruption.',
                      ).muted(),
                      const material.SizedBox(height: 16),
                      material.Container(
                        width: double.infinity,
                        padding: const material.EdgeInsets.all(12),
                        decoration: material.BoxDecoration(
                          color: colorScheme.muted.withOpacity(0.3),
                          borderRadius: material.BorderRadius.circular(6),
                          border: material.Border.all(
                            color: colorScheme.border,
                          ),
                        ),
                        child: material.SelectableText(
                          widget.error.toString(),
                          style: const material.TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const material.SizedBox(height: 16),
                        material.Container(
                          width: double.infinity,
                          padding: const material.EdgeInsets.all(10),
                          decoration: material.BoxDecoration(
                            color: (_isErrorStatus
                                    ? colorScheme.destructive
                                    : colorScheme.primary)
                                .withOpacity(0.15),
                            borderRadius: material.BorderRadius.circular(6),
                          ),
                          child: Text(
                            _statusMessage!,
                            style: material.TextStyle(
                              color: _isErrorStatus
                                  ? colorScheme.destructive
                                  : colorScheme.primary,
                              fontSize: 13,
                              fontWeight: material.FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const material.SizedBox(height: 24),
                      material.Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          PrimaryButton(
                            onPressed: _isBusy ? null : _handleRetry,
                            child: const Text('Retry Opening'),
                          ),
                          OutlineButton(
                            onPressed: _isBusy ? null : _handleUnlockWal,
                            child: const Text('Unlock Database (Clear WAL)'),
                          ),
                          OutlineButton(
                            onPressed: _isBusy ? null : _handleBackup,
                            child: const Text('Export / Backup querya.db'),
                          ),
                          GhostButton(
                            onPressed: _isBusy ? null : _handleSafeMode,
                            child: const Text('Start in Safe Mode'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
