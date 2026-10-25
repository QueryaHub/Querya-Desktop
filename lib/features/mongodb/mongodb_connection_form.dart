import 'package:querya_desktop/shared/report_error.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/connections/connection_test_result.dart';
import 'package:querya_desktop/features/connections/connection_default_name.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/features/connections/environment_section.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/ssh_tunnel_section.dart';
import 'package:querya_desktop/features/connections/forms/connection_auth_section.dart';
import 'package:querya_desktop/features/connections/forms/connection_host_port_section.dart';
import 'package:querya_desktop/features/connections/ssl_certificate_support.dart';
import 'package:querya_desktop/shared/widgets/form_validity_notifier.dart';
import 'package:querya_desktop/shared/widgets/ssl_certificate_fields.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// MongoDB connection form data.
class MongoConnectionData {
  MongoConnectionData({
    this.name = '',
    this.host = 'localhost',
    this.port = 27017,
    this.username,
    this.password,
    this.database,
    this.authSource,
    this.useSSL = false,
    this.connectionString,
  });

  final String name;
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String? database;
  final String? authSource;
  final bool useSSL;
  final String? connectionString;

  bool get isValid {
    if (connectionString != null && connectionString!.isNotEmpty) {
      return true; // connection string mode — just need the string
    }
    return name.trim().isNotEmpty && host.trim().isNotEmpty;
  }
}

/// Shows MongoDB connection form dialog.
/// Returns ConnectionRow if connection was created, null if cancelled.
Future<ConnectionRow?> showMongoConnectionForm(
  BuildContext context, {
  int? folderId,
  ConnectionRow? initial,
  ConnectionSaveGate? onSave,
}) async {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _MongoConnectionFormContent(
        folderId: folderId,
        initial: initial,
        onSave: onSave,
      ),
    ),
  );
}

class _MongoConnectionFormContent extends material.StatefulWidget {
  const _MongoConnectionFormContent({this.folderId, this.initial, this.onSave});

  final int? folderId;
  final ConnectionRow? initial;
  final ConnectionSaveGate? onSave;

  @override
  material.State<_MongoConnectionFormContent> createState() =>
      _MongoConnectionFormContentState();
}

class _MongoConnectionFormContentState
    extends material.State<_MongoConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _hostController = material.TextEditingController(text: 'localhost');
  final _portController = material.TextEditingController(text: '27017');
  final _usernameController = material.TextEditingController();
  final _passwordController = material.TextEditingController();
  final _databaseController = material.TextEditingController();
  final _authSourceController = material.TextEditingController();
  final _connectionStringController = material.TextEditingController();
  final _sslRootCertController = material.TextEditingController();
  final _sslCertController = material.TextEditingController();
  final _sslKeyController = material.TextEditingController();

  SshTunnelConfig _sshConfig = const SshTunnelConfig();
  ConnectionEnvironment? _environment;
  final SshTunnelSecrets _sshSecrets = SshTunnelSecrets();

  bool _useConnectionString = false;
  bool _useSSL = false;
  bool _removeSavedPassword = false;
  bool _isTesting = false;
  String? _testResult;
  Timer? _dismissTimer;
  late final FormValidityNotifier _formValidNotifier;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _formValidNotifier = FormValidityNotifier(() => _formData.isValid);
    for (final c in [
      _nameController,
      _hostController,
      _portController,
      _connectionStringController,
    ]) {
      _formValidNotifier.listenTo(c);
    }
    _connectionStringController.addListener(_populateSslFieldsFromUri);
    _sslRootCertController.addListener(_syncUriSslParams);
    _sslCertController.addListener(_syncUriSslParams);
    _sslKeyController.addListener(_syncUriSslParams);

    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _environment = initial.environment;
      _hostController.text = initial.host ?? 'localhost';
      _portController.text = (initial.port ?? 27017).toString();
      _usernameController.text = initial.username ?? '';
      _databaseController.text = initial.databaseName ?? '';
      _authSourceController.text = initial.authSource ?? '';
      _useSSL = initial.useSSL;
      final redacted = redactUriPassword(initial.connectionString) ?? '';
      _connectionStringController.text = redacted;
      if (redacted.isNotEmpty) {
        _useConnectionString = true;
      }
      if (initial.sshTunnelConfig != null) {
        _sshConfig = initial.sshTunnelConfig!;
      }
    }

    _formValidNotifier.seed();
  }

  void _populateSslFieldsFromUri() {
    populateSslControllersFromUri(
      _connectionStringController.text,
      rootCertController: _sslRootCertController,
      clientCertController: _sslCertController,
      clientKeyController: _sslKeyController,
    );
  }

  void _syncUriSslParams() {
    syncSslControllersIntoUri(
      _connectionStringController,
      rootCertController: _sslRootCertController,
      clientCertController: _sslCertController,
      clientKeyController: _sslKeyController,
    );
    _formValidNotifier.seed();
  }

  bool _hasSslCertificateFields() {
    return hasSslCertificateControllerValues(
      rootCertController: _sslRootCertController,
      clientCertController: _sslCertController,
      clientKeyController: _sslKeyController,
    );
  }

  String _buildConnectionUri() {
    final paths = sslPathsFromControllers(
      rootCertController: _sslRootCertController,
      clientCertController: _sslCertController,
      clientKeyController: _sslKeyController,
    );
    final user = _usernameController.text.trim();
    final pass = _passwordController.text;
    final db = _databaseController.text.trim();
    final authSource = _authSourceController.text.trim();
    final userInfoParts = <String>[
      if (user.isNotEmpty) Uri.encodeComponent(user),
      if (pass.isNotEmpty) Uri.encodeComponent(pass),
    ];
    final params = <String, String>{
      ...sslCertificateQueryParams(paths),
      if (authSource.isNotEmpty) 'authSource': authSource,
      if (_useSSL || paths.hasAny) 'ssl': 'true',
    };
    return Uri(
      scheme: 'mongodb',
      userInfo: userInfoParts.isEmpty ? null : userInfoParts.join(':'),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 27017,
      path: db.isEmpty ? null : '/$db',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  String? _effectiveConnectionString() {
    final uri = _connectionStringController.text.trim();
    if (_useConnectionString) {
      return uri.isEmpty ? null : uri;
    }
    if (_hasSslCertificateFields()) return _buildConnectionUri();
    return null;
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _connectionStringController.removeListener(_populateSslFieldsFromUri);
    _sslRootCertController.removeListener(_syncUriSslParams);
    _sslCertController.removeListener(_syncUriSslParams);
    _sslKeyController.removeListener(_syncUriSslParams);
    for (final c in [
      _nameController,
      _hostController,
      _portController,
      _connectionStringController,
    ]) {
      _formValidNotifier.unlistenFrom(c);
    }
    _formValidNotifier.dispose();
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    _authSourceController.dispose();
    _connectionStringController.dispose();
    _sslRootCertController.dispose();
    _sslCertController.dispose();
    _sslKeyController.dispose();
    super.dispose();
  }

  MongoConnectionData get _formData => MongoConnectionData(
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 27017,
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        password:
            _passwordController.text.isEmpty ? null : _passwordController.text,
        database: _databaseController.text.trim().isEmpty
            ? null
            : _databaseController.text.trim(),
        authSource: _authSourceController.text.trim().isEmpty
            ? null
            : _authSourceController.text.trim(),
        useSSL: _useSSL || _hasSslCertificateFields(),
        connectionString: _effectiveConnectionString(),
      );

  void _showTestResult(String result) {
    _dismissTimer?.cancel();
    setState(() {
      _isTesting = false;
      _testResult = result;
    });
    _dismissTimer = Timer(connectionTestResultLifetime(result), () {
      if (mounted) setState(() => _testResult = null);
    });
  }

  void _dismissResult() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() => _testResult = null);
  }

  Future<void> _testConnection() async {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final data = _formData;
      // Blank secret fields mean the saved ones when a connection is edited.
      final secrets = await secretsForConnectionTest(
        connectionId: widget.initial?.id,
        password: data.password,
        connectionString: data.connectionString,
        sshSecrets: _sshConfig.enabled ? _sshSecrets : null,
        useSavedPassword: !_removeSavedPassword,
      );
      final connection = MongoConnection(
        id: 0,
        name: data.name.isEmpty ? 'test' : data.name,
        host: data.host,
        port: data.port,
        username: data.username,
        password: secrets.password,
        database: data.database,
        authSource: data.authSource,
        useSSL: data.useSSL,
        connectionString: secrets.connectionString,
        sshConfig: _sshConfig.enabled ? _sshConfig : null,
        sshSecrets: secrets.sshSecrets,
      );

      final result = await connection.testConnection();
      await connection.disconnect();

      if (mounted) {
        _showTestResult(result.ok ? 'success' : (result.error ?? 'failed'));
      }
    } catch (e, st) {
      if (mounted) _showTestResult(failureMessage('error', e, where: 'MongoConnectionForm', stack: st, driver: DatabaseDriver.mongodb));
    }
  }

  bool _submitting = false;

  /// Closes the form with [row] once the save gate (creation flows) accepts it;
  /// when it refuses, the form stays open with everything typed and shows why
  /// (#1758).
  Future<void> _finish(ConnectionRow row) async {
    if (_submitting) return;
    _submitting = true;
    try {
      final error = await widget.onSave?.call(row);
      if (!mounted) return;
      if (error != null) {
        _showTestResult('error: $error');
        return;
      }
      material.Navigator.of(context).pop(row);
    } finally {
      _submitting = false;
    }
  }

  Future<void> _save() async {
    _syncUriSslParams();
    final data = _formData;
    if (!data.isValid) return;

    final displayName = data.name.isNotEmpty
        ? data.name
        : defaultConnectionName(
            label: 'MongoDB',
            defaultPort: 27017,
            uri: data.connectionString ?? '',
            fields: 'MongoDB ${data.host}:${data.port}',
          );

    final initial = widget.initial;
    var row = ConnectionRow(
      id: initial?.id,
      type: initial?.type ?? 'mongodb',
      name: displayName,
      host: data.host,
      port: data.port,
      username: data.username,
      password: data.password,
      databaseName: data.database,
      authSource: data.authSource,
      useSSL: data.useSSL,
      connectionString: data.connectionString,
      extensionId: initial?.extensionId,
      driverOptions: initial?.driverOptions,
      folderId: initial?.folderId ?? widget.folderId,
      sortOrder: initial?.sortOrder ?? 0,
      createdAt: initial?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      sshSecrets: _sshConfig.enabled ? _sshSecrets : null,
    );
    row = row.withSshTunnelConfig(_sshConfig.enabled ? _sshConfig : null);
    row = row.withEnvironment(_environment);
    row = row.copyWith(removeSavedPassword: _removeSavedPassword);

    await _finish(row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: WindowLayout.connectionFormMaxWidth,
        maxHeight: WindowLayout.connectionFormMongoMaxHeight,
      ),
      borderColor: theme.muted,
      child: material.FocusTraversalGroup(
        policy: material.WidgetOrderTraversalPolicy(),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      material.Icon(
                        material.Icons.eco_rounded,
                        size: 24,
                        color: theme.primary,
                      ),
                      const Gap(12),
                      Text(
                        _isEditing
                            ? 'Edit MongoDB Connection'
                            : 'MongoDB Connection',
                      ).large().semiBold(),
                    ],
                  ),
                  const Gap(8),
                  const Text('Configure your MongoDB connection settings')
                      .muted()
                      .small(),
                ],
              ),
            ),
            const QueryaDivider(height: 1),
            material.Expanded(
              child: material.FocusTraversalGroup(
                policy: material.WidgetOrderTraversalPolicy(),
                child: material.SingleChildScrollView(
                  padding: const material.EdgeInsets.all(24),
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
                    children: [
                      // Connection string toggle
                      material.Row(
                        children: [
                          material.Checkbox(
                            value: _useConnectionString,
                            onChanged: (v) {
                              setState(() => _useConnectionString = v ?? false);
                              _formValidNotifier.seed();
                            },
                          ),
                          const Gap(8),
                          const Text('Use connection string').small(),
                        ],
                      ),
                    const Gap(16),
                    if (_useConnectionString) ...[
                      const Text('Connection String').small().semiBold(),
                      const Gap(8),
                      QueryaTextField(
                        controller: _connectionStringController,
                        placeholder: 'mongodb://username:password@host:port/database',
                        maxLines: 2,
                      ),
                      const Gap(16),
                      material.Row(
                        children: [
                          material.Checkbox(
                            value: _useSSL,
                            onChanged: (v) =>
                                setState(() => _useSSL = v ?? false),
                          ),
                          const Gap(8),
                          const Text('Use SSL/TLS').small(),
                        ],
                      ),
                      if (_useSSL) ...[
                        const Gap(16),
                        SslCertificateFields(
                          rootCertController: _sslRootCertController,
                          clientCertController: _sslCertController,
                          clientKeyController: _sslKeyController,
                          onChanged: _syncUriSslParams,
                        ),
                      ],
                    ] else ...[
                      // Connection name
                      const Text('Connection Name').small().semiBold(),
                      const Gap(8),
                      QueryaTextField(
                        controller: _nameController,
                        placeholder: 'My MongoDB Server',
                      ),
                      const Gap(16),
                      // Host and Port
                      ConnectionHostPortSection(
                        hostController: _hostController,
                        portController: _portController,
                        portPlaceholder: '27017',
                        portFlex: 1,
                        gap: 12,
                      ),
                      const Gap(16),
                      // Authentication
                      ConnectionAuthSection(
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        usernameLabel: 'Authentication (Optional)',
                        usernamePlaceholder: 'Username',
                        isEditing: _isEditing,
                        removeSavedPassword: _removeSavedPassword,
                        onRemoveSavedPasswordChanged: (v) =>
                            setState(() => _removeSavedPassword = v),
                        useRowLayout: false,
                      ),
                      const Gap(16),
                      // Database and Auth Source
                      material.Row(
                        children: [
                          material.Expanded(
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              mainAxisSize: material.MainAxisSize.min,
                              children: [
                                const Text('Default Database (Optional)')
                                    .small()
                                    .semiBold(),
                                const Gap(8),
                                QueryaTextField(
                                  controller: _databaseController,
                                  placeholder: 'admin',
                                ),
                              ],
                            ),
                          ),
                          const Gap(12),
                          material.Expanded(
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              mainAxisSize: material.MainAxisSize.min,
                              children: [
                                const Text('Auth Source (Optional)')
                                    .small()
                                    .semiBold(),
                                const Gap(8),
                                QueryaTextField(
                                  controller: _authSourceController,
                                  placeholder: 'admin',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // SSL
                      material.Row(
                        children: [
                          material.Checkbox(
                            value: _useSSL,
                            onChanged: (v) =>
                                setState(() => _useSSL = v ?? false),
                          ),
                          const Gap(8),
                          const Text('Use SSL/TLS').small(),
                        ],
                      ),
                      if (_useSSL) ...[
                        const Gap(16),
                        SslCertificateFields(
                          rootCertController: _sslRootCertController,
                          clientCertController: _sslCertController,
                          clientKeyController: _sslKeyController,
                          onChanged: _syncUriSslParams,
                        ),
                      ],
                      const Gap(16),
                      EnvironmentSection(
                        value: _environment,
                        onChanged: (e) => setState(() => _environment = e),
                      ),
                      const Gap(16),
                      // SSH Tunneling Section
                      SshTunnelSection(
                        config: _sshConfig,
                        secrets: _sshSecrets,
                        connectionId: widget.initial?.id,
                        onChanged: (cfg) => setState(() => _sshConfig = cfg),
                        targetHost: _hostController.text.trim().isNotEmpty
                            ? _hostController.text.trim()
                            : 'localhost',
                        targetPort:
                            int.tryParse(_portController.text.trim()) ?? 27017,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ),
            const QueryaDivider(height: 1),
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
                              connectionTestMessage(_testResult!),
                              style: material.TextStyle(
                                fontSize: 13,
                                color: theme.foreground,
                              ),
                            ).small(),
                          ),
                          QueryaIconButton(
icon: const material.Icon(material.Icons.close),
tooltip: 'Dismiss',
size: QueryaControlSize.sm,
onPressed: _dismissResult,
),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            material.FocusTraversalGroup(
              policy: material.WidgetOrderTraversalPolicy(),
              child: ValueListenableBuilder<bool>(
                valueListenable: _formValidNotifier.listenable,
                builder: (context, formValid, _) => QueryaDialogActions(
                  secondary: [
                    QueryaButton.secondary(
                          label: 'Test Connection',
                          icon: material.Icons.link_rounded,
                          loading: _isTesting,
                          size: QueryaControlSize.lg,
                          onPressed: formValid && !_isTesting ? _testConnection : null,
                        ),
                  ],
                  cancel: QueryaButton.ghost(
                          label: 'Cancel',
                          onPressed: () => material.Navigator.of(context).pop(),
                          size: QueryaControlSize.lg,
                        ),
                  primary: QueryaButton.primary(
                          label: 'Save',
                          onPressed: formValid ? _save : null,
                          size: QueryaControlSize.lg,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
