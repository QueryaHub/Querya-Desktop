import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/sdui/sdui_form_builder.dart';
import 'package:querya_desktop/core/sdui/sdui_form_schema.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows an SDUI connection form for an installed extension driver.
Future<ConnectionRow?> showExtensionConnectionForm(
  material.BuildContext context, {
  required ExtensionManifest manifest,
  required DriverContribution driver,
  int? folderId,
}) {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _ExtensionConnectionFormContent(
        manifest: manifest,
        driver: driver,
        folderId: folderId,
      ),
    ),
  );
}

class _ExtensionConnectionFormContent extends material.StatefulWidget {
  const _ExtensionConnectionFormContent({
    required this.manifest,
    required this.driver,
    this.folderId,
  });

  final ExtensionManifest manifest;
  final DriverContribution driver;
  final int? folderId;

  @override
  material.State<_ExtensionConnectionFormContent> createState() =>
      _ExtensionConnectionFormContentState();
}

class _ExtensionConnectionFormContentState
    extends material.State<_ExtensionConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _formKey = material.GlobalKey<SduiFormBuilderState>();
  SduiFormSchema? _schema;
  String? _loadError;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.driver.displayName;
    _loadSchema();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSchema() async {
    try {
      final schema = await loadDriverConnectionFormSchema(
        manifest: widget.manifest,
        driver: widget.driver,
      );
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _loading = false;
        _loadError = schema == null
            ? 'Connection form schema not found for this driver.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Failed to load connection form: $e';
      });
    }
  }

  void _save() {
    final schema = _schema;
    if (schema == null) return;
    final values = _formKey.currentState?.collectValues();
    if (values == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final row = connectionRowFromExtensionForm(
      manifest: widget.manifest,
      driver: widget.driver,
      name: name,
      values: values,
      folderId: widget.folderId,
    );
    material.Navigator.of(context).pop(row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
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
                  Text(widget.driver.displayName).large().semiBold(),
                  const material.SizedBox(height: 6),
                  Text(
                    'Extension driver · ${widget.manifest.id}',
                  ).muted().small(),
                ],
              ),
            ),
            material.Flexible(
              child: material.SingleChildScrollView(
                padding: const material.EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    const Text('Connection name').small().muted(),
                    const material.SizedBox(height: 4),
                    TextField(
                      controller: _nameController,
                      placeholder: const Text('My ClickHouse'),
                    ),
                    const material.SizedBox(height: 16),
                    if (_loading)
                      const material.Padding(
                        padding: material.EdgeInsets.all(24),
                        child: material.Center(
                          child: material.CircularProgressIndicator(),
                        ),
                      )
                    else if (_loadError != null)
                      Text(_loadError!).muted().small()
                    else if (_schema != null)
                      SduiFormBuilder(key: _formKey, schema: _schema!),
                  ],
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
              child: material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  GhostButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const material.SizedBox(width: 12),
                  PrimaryButton(
                    onPressed: _schema == null ? null : _save,
                    child: const Text('Save'),
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

/// Loads SDUI form schema from the extension package (file path preferred).
Future<SduiFormSchema?> loadDriverConnectionFormSchema({
  required ExtensionManifest manifest,
  required DriverContribution driver,
}) async {
  final rel = driver.connectionFormSchema?.trim();
  final root = manifest.installPath;
  if (rel != null && rel.isNotEmpty && root != null && root.isNotEmpty) {
    final file = File(p.join(root, rel));
    if (await file.exists()) {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        return SduiFormSchema.fromJson(raw);
      }
      if (raw is Map) {
        return SduiFormSchema.fromJson(Map<String, dynamic>.from(raw));
      }
    }
  }
  return null;
}

/// Maps SDUI form values into a [ConnectionRow] for an extension driver.
ConnectionRow connectionRowFromExtensionForm({
  required ExtensionManifest manifest,
  required DriverContribution driver,
  required String name,
  required Map<String, Object?> values,
  int? folderId,
}) {
  final known = {'host', 'port', 'username', 'password', 'database', 'databaseName'};
  final host = values['host']?.toString().trim();
  final portRaw = values['port'];
  int? port;
  if (portRaw is int) {
    port = portRaw;
  } else if (portRaw != null) {
    port = int.tryParse('$portRaw');
  }
  port ??= driver.defaultPort;

  final username = values['username']?.toString();
  final password = values['password']?.toString();
  final database = (values['database'] ?? values['databaseName'])?.toString();

  final sslMode = values['sslMode']?.toString().toLowerCase();
  final useSsl = sslMode != null
      ? sslMode != 'disable' && sslMode != 'false' && sslMode != '0'
      : values['ssl'] == true || values['useSSL'] == true;

  final options = <String, Object?>{};
  for (final entry in values.entries) {
    if (known.contains(entry.key)) continue;
    if (entry.key == 'password') continue;
    options[entry.key] = entry.value;
  }

  return ConnectionRow(
    type: driver.driverId,
    name: name,
    host: (host == null || host.isEmpty) ? null : host,
    port: port,
    username: username,
    password: (password == null || password.isEmpty) ? null : password,
    databaseName: database,
    useSSL: useSsl,
    extensionId: manifest.id,
    driverOptions: options.isEmpty ? null : jsonEncode(options),
    folderId: folderId,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}
