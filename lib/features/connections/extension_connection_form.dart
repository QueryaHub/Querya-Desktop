import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/sdui/sdui_form_builder.dart';
import 'package:querya_desktop/core/sdui/sdui_form_schema.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_edit_secrets.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows an SDUI connection form for an installed extension driver.
Future<ConnectionRow?> showExtensionConnectionForm(
  material.BuildContext context, {
  required ExtensionManifest manifest,
  required DriverContribution driver,
  int? folderId,
  ConnectionRow? initial,
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
        initial: initial,
      ),
    ),
  );
}

class _ExtensionConnectionFormContent extends material.StatefulWidget {
  const _ExtensionConnectionFormContent({
    required this.manifest,
    required this.driver,
    this.folderId,
    this.initial,
  });

  final ExtensionManifest manifest;
  final DriverContribution driver;
  final int? folderId;
  final ConnectionRow? initial;

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
  var _testing = false;
  String? _testMessage;
  bool _testSucceeded = false;
  late final Map<String, Object?> _initialValues;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _initialValues = _sduiInitialValuesFromConnection(initial);
    } else {
      _nameController.text = widget.driver.displayName;
      _initialValues = const {};
    }
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
      initial: widget.initial,
    );
    material.Navigator.of(context).pop(row);
  }

  Future<void> _testConnection() async {
    final schema = _schema;
    if (schema == null) return;

    final formState = _formKey.currentState;
    if (formState == null) return;

    final values = formState.collectValues();
    if (values == null) {
      if (!mounted) return;
      setState(() {
        _testMessage = 'Fill in all required fields before testing.';
        _testSucceeded = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMessage = null;
      _testSucceeded = false;
    });

    try {
      var row = connectionRowFromExtensionForm(
        manifest: widget.manifest,
        driver: widget.driver,
        name: 'connection-test',
        values: values,
        initial: widget.initial,
      );
      if (widget.initial?.id != null) {
        row = await mergeSecretsForConnectionUpdate(row);
      }
      final version = await ExtensionDriverSession.instance.testConnection(
        manifest: widget.manifest,
        row: row,
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSucceeded = true;
        _testMessage = version.isEmpty
            ? 'Connection successful.'
            : 'Connection successful — server version $version.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSucceeded = false;
        _testMessage = 'Connection failed: $e';
      });
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    final title = _isEditing
        ? 'Edit ${widget.driver.displayName}'
        : widget.driver.displayName;
    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: WindowLayout.connectionFormMaxWidth,
        minWidth: 440,
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
                  Text(title).large().semiBold(),
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
                      SduiFormBuilder(
                        key: _formKey,
                        schema: _schema!,
                        initialValues: _initialValues,
                        keepExistingSecrets: _isEditing,
                      ),
                    if (_testMessage != null) ...[
                      const material.SizedBox(height: 12),
                      material.SelectableText(
                        _testMessage!,
                        style: material.TextStyle(
                          fontSize: 12,
                          color: _testSucceeded
                              ? material.Colors.green
                              : theme.destructive,
                        ),
                      ),
                    ],
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
                children: [
                  OutlineButton(
                    onPressed:
                        _schema == null || _testing ? null : _testConnection,
                    leading: _testing
                        ? const material.SizedBox(
                            width: 14,
                            height: 14,
                            child: material.CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const material.Icon(
                            material.Icons.bolt_rounded,
                            size: 16,
                          ),
                    child: const Text('Test Connection'),
                  ),
                  const Spacer(),
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
    );
  }
}

/// Non-secret SDUI seed values from an existing [ConnectionRow] (no passwords).
Map<String, Object?> _sduiInitialValuesFromConnection(ConnectionRow row) {
  final values = <String, Object?>{};

  final optionsRaw = row.driverOptions;
  if (optionsRaw != null && optionsRaw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(optionsRaw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          if (_isPasswordKey(key)) continue;
          values[key] = entry.value;
        }
      }
    } catch (_) {
      // Ignore malformed driverOptions; host fields still apply.
    }
  }

  final host = row.host;
  if (host != null && host.isNotEmpty) values['host'] = host;
  if (row.port != null) values['port'] = row.port;
  final username = row.username;
  if (username != null && username.isNotEmpty) values['username'] = username;
  final database = row.databaseName;
  if (database != null && database.isNotEmpty) {
    values['database'] = database;
    values['databaseName'] = database;
  }
  values['useSSL'] = row.useSSL;
  values['ssl'] = row.useSSL;
  if (row.useSSL) {
    values.putIfAbsent('sslMode', () => 'require');
  }

  values.removeWhere((key, _) => _isPasswordKey(key));
  return values;
}

bool _isPasswordKey(String key) {
  final lower = key.toLowerCase();
  return lower == 'password' ||
      lower.endsWith('password') ||
      lower.contains('secret') ||
      lower.contains('passwd');
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
  ConnectionRow? initial,
}) {
  final known = {
    'host',
    'port',
    'username',
    'password',
    'database',
    'databaseName',
    'sslMode',
  };
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
    id: initial?.id,
    type: initial?.type ?? driver.driverId,
    name: name,
    host: (host == null || host.isEmpty) ? null : host,
    port: port,
    username: username,
    password: (password == null || password.isEmpty) ? null : password,
    databaseName: database,
    useSSL: useSsl,
    extensionId: initial?.extensionId ?? manifest.id,
    driverOptions: options.isEmpty ? null : jsonEncode(options),
    folderId: initial?.folderId ?? folderId,
    sortOrder: initial?.sortOrder ?? 0,
    createdAt: initial?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
  );
}
