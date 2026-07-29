import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/form_validity_notifier.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows SQLite connection form dialog.
/// Returns ConnectionRow if saved, null if cancelled.
Future<ConnectionRow?> showSqliteConnectionForm(
  material.BuildContext context, {
  int? folderId,
  ConnectionRow? initial,
}) async {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _SqliteConnectionFormContent(
        folderId: folderId,
        initial: initial,
      ),
    ),
  );
}

class _SqliteConnectionFormContent extends material.StatefulWidget {
  const _SqliteConnectionFormContent({this.folderId, this.initial});

  final int? folderId;
  final ConnectionRow? initial;

  @override
  material.State<_SqliteConnectionFormContent> createState() =>
      _SqliteConnectionFormContentState();
}

class _SqliteConnectionFormContentState
    extends material.State<_SqliteConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _pathController = material.TextEditingController();

  bool _readOnly = false;
  bool _isTesting = false;
  String? _testResult;
  Timer? _dismissTimer;
  late final FormValidityNotifier _formValidNotifier;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _formValidNotifier = FormValidityNotifier(_computeFormValid);
    _formValidNotifier.listenTo(_nameController);
    _formValidNotifier.listenTo(_pathController);

    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _pathController.text = initial.host ?? '';
      _readOnly = initial.useSSL;
    }

    _formValidNotifier.seed();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    _dismissTimer?.cancel();
    _formValidNotifier.dispose();
    super.dispose();
  }

  bool _computeFormValid() {
    final path = _pathController.text.trim();
    final name = _nameController.text.trim();
    return path.isNotEmpty && name.isNotEmpty;
  }

  void _showTestResult(String result) {
    _dismissTimer?.cancel();
    setState(() {
      _isTesting = false;
      _testResult = result;
    });
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _testResult = null);
    });
  }

  void _dismissResult() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() => _testResult = null);
  }

  Future<void> _pickFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'SQLite Databases',
            extensions: ['db', 'sqlite', 'sqlite3', 'db3'],
          ),
        ],
      );
      if (file == null) return;
      final path = file.path;
      if (path.isEmpty) return;
      _pathController.text = path;
      if (_nameController.text.isEmpty) {
        _nameController.text = p.basenameWithoutExtension(path);
      }
    } catch (_) {}
  }

  Future<void> _testConnection() async {
    if (!_formValidNotifier.value) return;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final conn = SqliteConnection(
        id: 0,
        name: _nameController.text.trim(),
        path: _pathController.text.trim(),
        readOnly: _readOnly,
      );
      final ok = await conn.testConnection();
      if (!mounted) return;
      if (ok) {
        _showTestResult('success');
      } else {
        _showTestResult('error:Failed to open SQLite database.');
      }
    } catch (e) {
      if (!mounted) return;
      _showTestResult('error:$e');
    }
  }

  void _save() {
    if (!_formValidNotifier.value) return;
    final initial = widget.initial;
    final row = ConnectionRow(
      id: initial?.id,
      type: initial?.type ?? 'sqlite',
      name: _nameController.text.trim(),
      host: _pathController.text.trim(),
      useSSL: _readOnly, // Store read-only toggle in useSSL field
      extensionId: initial?.extensionId,
      driverOptions: initial?.driverOptions,
      createdAt: initial?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      folderId: initial?.folderId ?? widget.folderId,
      sortOrder: initial?.sortOrder ?? 0,
    );
    material.Navigator.of(context).pop(row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    final dialogMaxW = WindowLayout.newConnectionDialogMaxWidth(context);
    final dialogH = WindowLayout.newConnectionDialogHeight(context);
    final scrollH = dialogH - 120.0; // Subtract header and footer heights

    return material.SizedBox(
      width: dialogMaxW,
      child: QueryaDialogCard(
        constraints: material.BoxConstraints(
          maxWidth: dialogMaxW,
          maxHeight: dialogH,
        ),
        borderColor: theme.muted,
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            // Header
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isEditing
                        ? 'Edit SQLite Connection'
                        : 'New SQLite Connection',
                  ).large().semiBold(),
                  const Gap(6),
                  const Text('Connect to a local SQLite database file.')
                      .muted()
                      .small(),
                ],
              ),
            ),
            // Form body
            material.ConstrainedBox(
              constraints: material.BoxConstraints(
                maxHeight: scrollH,
              ),
              child: material.SingleChildScrollView(
                physics: const material.ClampingScrollPhysics(),
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    // Connection Name
                    const Text('Connection name').small().semiBold(),
                    const Gap(8),
                    TextField(
                      controller: _nameController,
                      placeholder: const Text('e.g. Local Cache'),
                    ),
                    const Gap(16),
                    // Database File Path
                    const Text('Database file path').small().semiBold(),
                    const Gap(8),
                    material.Row(
                      children: [
                        material.Expanded(
                          child: TextField(
                            controller: _pathController,
                            placeholder: const Text('/path/to/database.db'),
                          ),
                        ),
                        const Gap(10),
                        OutlineButton(
                          onPressed: _pickFile,
                          child: const Text('Browse…'),
                        ),
                      ],
                    ),
                    const Gap(16),
                    // Read-only toggle
                    material.Row(
                      children: [
                        material.Checkbox(
                          value: _readOnly,
                          onChanged: (v) =>
                              setState(() => _readOnly = v ?? false),
                        ),
                        const Gap(8),
                        const Text('Read-only mode').small(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const material.Divider(height: 1),
            // Test result banner
            if (_testResult != null)
              material.Padding(
                padding: const material.EdgeInsets.fromLTRB(24, 8, 16, 8),
                child: material.Material(
                  color: material.Colors.transparent,
                  child: material.InkWell(
                    onTap: _dismissResult,
                    borderRadius: material.BorderRadius.circular(8),
                    child: material.Container(
                      padding: const material.EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: material.BoxDecoration(
                        color: _testResult == 'success'
                            ? theme.primary.withValues(alpha: 0.12)
                            : theme.destructive.withValues(alpha: 0.12),
                        borderRadius: material.BorderRadius.circular(8),
                        border: material.Border.all(
                          color: _testResult == 'success'
                              ? theme.primary.withValues(alpha: 0.35)
                              : theme.destructive.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: material.Row(
                        children: [
                          material.Icon(
                            _testResult == 'success'
                                ? material.Icons.check_circle_outline
                                : material.Icons.info_outline_rounded,
                            size: 18,
                            color: _testResult == 'success'
                                ? theme.primary
                                : theme.destructive,
                          ),
                          const Gap(10),
                          material.Expanded(
                            child: Text(
                              _testResult == 'success'
                                  ? 'Connection successful!'
                                  : _testResult!.startsWith('error:')
                                      ? _testResult!.substring(7)
                                      : 'Connection failed',
                              style: material.TextStyle(
                                fontSize: 13,
                                color: theme.foreground,
                              ),
                            ).small(),
                          ),
                          material.IconButton(
                            icon: material.Icon(
                              material.Icons.close,
                              size: 18,
                              color: theme.mutedForeground,
                            ),
                            onPressed: _dismissResult,
                            style: material.IconButton.styleFrom(
                              minimumSize: const material.Size(28, 28),
                              padding: material.EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Footer
            material.Container(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              child: ValueListenableBuilder<bool>(
                valueListenable: _formValidNotifier.listenable,
                builder: (context, formValid, _) {
                  return material.Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: material.WrapAlignment.spaceBetween,
                    children: [
                      OutlineButton(
                        onPressed:
                            formValid && !_isTesting ? _testConnection : null,
                        leading: _isTesting
                            ? material.SizedBox(
                                width: 18,
                                height: 18,
                                child: material.CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.primary,
                                ),
                              )
                            : material.Icon(
                                material.Icons.link_rounded,
                                size: 18,
                                color: formValid
                                    ? theme.primary
                                    : theme.mutedForeground,
                              ),
                        child: Text(
                          'Test Connection',
                          style: material.TextStyle(
                            fontWeight: material.FontWeight.w500,
                            color: formValid
                                ? theme.primary
                                : theme.mutedForeground,
                          ),
                        ),
                      ),
                      material.Row(
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          GhostButton(
                            onPressed: () =>
                                material.Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const Gap(12),
                          PrimaryButton(
                            onPressed: formValid ? _save : null,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
