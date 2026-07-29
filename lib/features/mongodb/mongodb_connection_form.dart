import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/ssl_certificate_support.dart';
import 'package:querya_desktop/shared/widgets/form_validity_notifier.dart';
import 'package:querya_desktop/shared/widgets/ssl_certificate_fields.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

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
}) async {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _MongoConnectionFormContent(
        folderId: folderId,
        initial: initial,
      ),
    ),
  );
}

class _MongoConnectionFormContent extends material.StatefulWidget {
  const _MongoConnectionFormContent({this.folderId, this.initial});

  final int? folderId;
  final ConnectionRow? initial;

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

  bool _useConnectionString = false;
  bool _useSSL = false;
  bool _showPassword = false;
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
    _dismissTimer = Timer(const Duration(seconds: 5), () {
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
      final connection = MongoConnection(
        id: 0,
        name: data.name.isEmpty ? 'test' : data.name,
        host: data.host,
        port: data.port,
        username: data.username,
        password: data.password,
        database: data.database,
        authSource: data.authSource,
        useSSL: data.useSSL,
        connectionString: data.connectionString,
      );

      final success = await connection.testConnection();
      await connection.disconnect();

      if (mounted) _showTestResult(success ? 'success' : 'failed');
    } catch (e) {
      if (mounted) _showTestResult('error: $e');
    }
  }

  void _save() {
    _syncUriSslParams();
    final data = _formData;
    if (!data.isValid) return;

    final displayName =
        data.name.isNotEmpty ? data.name : 'MongoDB ${data.host}:${data.port}';

    final initial = widget.initial;
    final row = ConnectionRow(
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
    );

    material.Navigator.of(context).pop(row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: WindowLayout.connectionFormMaxWidth,
        maxHeight: WindowLayout.connectionFormMongoMaxHeight,
      ),
      borderColor: theme.muted,
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
            const material.Divider(height: 1),
            material.Expanded(
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
                      TextField(
                        controller: _connectionStringController,
                        placeholder: const Text(
                            'mongodb://username:password@host:port/database'),
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
                      TextField(
                        controller: _nameController,
                        placeholder: const Text('My MongoDB Server'),
                      ),
                      const Gap(16),
                      // Host and Port
                      material.Row(
                        children: [
                          material.Expanded(
                            flex: 3,
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              mainAxisSize: material.MainAxisSize.min,
                              children: [
                                const Text('Host').small().semiBold(),
                                const Gap(8),
                                TextField(
                                  controller: _hostController,
                                  placeholder: const Text('localhost'),
                                ),
                              ],
                            ),
                          ),
                          const Gap(12),
                          material.Expanded(
                            flex: 1,
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              mainAxisSize: material.MainAxisSize.min,
                              children: [
                                const Text('Port').small().semiBold(),
                                const Gap(8),
                                TextField(
                                  controller: _portController,
                                  placeholder: const Text('27017'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Gap(16),
                      // Authentication
                      const Text('Authentication (Optional)')
                          .small()
                          .semiBold(),
                      const Gap(8),
                      TextField(
                        controller: _usernameController,
                        placeholder: const Text('Username'),
                      ),
                      const Gap(12),
                      material.Stack(
                        children: [
                          TextField(
                            controller: _passwordController,
                            placeholder: Text(
                              _isEditing
                                  ? 'Leave blank to keep existing'
                                  : 'Password',
                            ),
                            obscureText: !_showPassword,
                          ),
                          material.Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: material.Center(
                              child: material.IconButton(
                                icon: material.Icon(
                                  _showPassword
                                      ? material.Icons.visibility_off
                                      : material.Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                                padding: material.EdgeInsets.zero,
                                constraints: const material.BoxConstraints(),
                              ),
                            ),
                          ),
                        ],
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
                                TextField(
                                  controller: _databaseController,
                                  placeholder: const Text('admin'),
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
                                TextField(
                                  controller: _authSourceController,
                                  placeholder: const Text('admin'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Gap(16),
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
                    ],
                  ],
                ),
              ),
            ),
            const material.Divider(height: 1),
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
            material.Container(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              child: ValueListenableBuilder<bool>(
                valueListenable: _formValidNotifier.listenable,
                builder: (context, formValid, _) {
                  return material.Row(
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
                      const material.Spacer(),
                      GhostButton(
                        onPressed: () => material.Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const Gap(12),
                      PrimaryButton(
                        onPressed: formValid ? _save : null,
                        child: const Text('Save'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
    );
  }
}
