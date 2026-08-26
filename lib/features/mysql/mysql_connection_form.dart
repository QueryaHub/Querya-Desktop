import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/ssl_certificate_support.dart';
import 'package:querya_desktop/shared/widgets/form_validity_notifier.dart';
import 'package:querya_desktop/shared/widgets/ssl_certificate_fields.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows MySQL / MariaDB connection form dialog.
/// Returns [ConnectionRow] if saved, null if cancelled.
Future<ConnectionRow?> showMysqlConnectionForm(
  BuildContext context, {
  int? folderId,
  ConnectionRow? initial,
}) async {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _MysqlConnectionFormContent(
        folderId: folderId,
        initial: initial,
      ),
    ),
  );
}

class _MysqlConnectionFormContent extends material.StatefulWidget {
  const _MysqlConnectionFormContent({this.folderId, this.initial});

  final int? folderId;
  final ConnectionRow? initial;

  @override
  material.State<_MysqlConnectionFormContent> createState() =>
      _MysqlConnectionFormContentState();
}

class _MysqlConnectionFormContentState
    extends material.State<_MysqlConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _hostController = material.TextEditingController(text: 'localhost');
  final _portController = material.TextEditingController(text: '3306');
  final _databaseController = material.TextEditingController();
  final _usernameController = material.TextEditingController(text: 'root');
  final _passwordController = material.TextEditingController();
  final _connectionStringController = material.TextEditingController();
  final _sslRootCertController = material.TextEditingController();
  final _sslCertController = material.TextEditingController();
  final _sslKeyController = material.TextEditingController();

  bool _useSSL = true;
  bool _showPassword = false;
  bool _isTesting = false;
  String? _testResult;
  Timer? _dismissTimer;
  late final FormValidityNotifier _formValidNotifier;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _formValidNotifier = FormValidityNotifier(_computeFormValid);
    for (final c in [
      _nameController,
      _hostController,
      _portController,
      _databaseController,
      _usernameController,
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
      _hostController.text = initial.host ?? '';
      _portController.text = (initial.port ?? 3306).toString();
      _usernameController.text = initial.username ?? '';
      _databaseController.text = initial.databaseName ?? '';
      _useSSL = initial.useSSL;
      _connectionStringController.text =
          redactUriPassword(initial.connectionString) ?? '';
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
    final userInfoParts = <String>[
      if (user.isNotEmpty) Uri.encodeComponent(user),
      if (pass.isNotEmpty) Uri.encodeComponent(pass),
    ];
    final params = <String, String>{
      ...sslCertificateQueryParams(paths),
      if (!_useSSL) 'ssl-mode': 'disable',
    };
    return Uri(
      scheme: 'mysql',
      userInfo: userInfoParts.isEmpty ? null : userInfoParts.join(':'),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 3306,
      path: db.isEmpty ? null : '/$db',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  String _effectiveConnectionUri() {
    final uri = _connectionStringController.text.trim();
    if (uri.isNotEmpty) return uri;
    if (!_hasSslCertificateFields()) return '';
    return _buildConnectionUri();
  }

  bool _looksLikeMysqlUri(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('mysql://') || t.startsWith('mariadb://');
  }

  bool _computeFormValid() {
    final uri = _connectionStringController.text.trim();
    if (uri.isNotEmpty) {
      return _looksLikeMysqlUri(uri);
    }
    final host = _hostController.text.trim();
    return host.isNotEmpty;
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

  Future<void> _testConnection() async {
    if (!_formValidNotifier.value) return;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final uri = _effectiveConnectionUri();
      final dbText = _databaseController.text.trim();
      final conn = MysqlConnection(
        id: 0,
        name: _nameController.text.trim().isEmpty
            ? 'test'
            : _nameController.text.trim(),
        host: uri.isNotEmpty ? 'localhost' : _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 3306,
        database: dbText.isEmpty ? null : dbText,
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        password:
            _passwordController.text.isEmpty ? null : _passwordController.text,
        useSSL: _useSSL || _hasSslCertificateFields(),
        connectionString: uri.isEmpty ? null : uri,
      );
      final ok = await conn.testConnection();
      if (mounted) _showTestResult(ok ? 'success' : 'failed');
    } catch (e) {
      if (mounted) _showTestResult('error: $e');
    }
  }

  void _save() {
    if (!_formValidNotifier.value) return;
    _syncUriSslParams();
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3306;
    final database = _databaseController.text.trim();
    final uri = _effectiveConnectionUri();
    final displayName = name.isNotEmpty
        ? name
        : (uri.isNotEmpty
            ? 'MySQL (URI)'
            : 'MySQL $host:$port${database.isNotEmpty ? '/$database' : ''}');
    final initial = widget.initial;
    final row = ConnectionRow(
      id: initial?.id,
      type: initial?.type ?? 'mysql',
      name: displayName,
      host: uri.isNotEmpty ? null : host,
      port: uri.isNotEmpty ? null : port,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      password:
          _passwordController.text.isEmpty ? null : _passwordController.text,
      databaseName:
          uri.isNotEmpty ? null : (database.isEmpty ? null : database),
      useSSL: _useSSL || _hasSslCertificateFields(),
      connectionString: uri.isEmpty ? null : uri,
      extensionId: initial?.extensionId,
      driverOptions: initial?.driverOptions,
      folderId: initial?.folderId ?? widget.folderId,
      sortOrder: initial?.sortOrder ?? 0,
      createdAt: initial?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
    );
    material.Navigator.of(context).pop(row);
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
      _databaseController,
      _usernameController,
      _connectionStringController,
    ]) {
      _formValidNotifier.unlistenFrom(c);
    }
    _formValidNotifier.dispose();
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _connectionStringController.dispose();
    _sslRootCertController.dispose();
    _sslCertController.dispose();
    _sslKeyController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: WindowLayout.connectionFormMaxWidth,
        maxHeight: WindowLayout.connectionFormMaxHeight,
      ),
      borderColor: theme.muted,
      child: material.FocusTraversalGroup(
        policy: material.WidgetOrderTraversalPolicy(),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Row(
                    children: [
                      material.SizedBox(
                        width: 24,
                        height: 24,
                        child: material.Image.asset(
                          'assets/images/mysql_icon.png',
                          cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                          cacheHeight: (40 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                          fit: material.BoxFit.contain,
                          errorBuilder: (_, __, ___) => material.Icon(
                            material.Icons.table_chart_rounded,
                            size: 24,
                            color: theme.primary,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Text(
                        _isEditing
                            ? 'Edit MySQL Connection'
                            : 'MySQL Connection',
                      ).large().semiBold(),
                    ],
                  ),
                  const Gap(8),
                  const Text('Configure your MySQL or MariaDB connection')
                      .muted()
                      .small(),
                ],
              ),
            ),
            const material.Divider(height: 1),
            material.Expanded(
              child: material.FocusTraversalGroup(
                policy: material.WidgetOrderTraversalPolicy(),
                child: material.SingleChildScrollView(
                  padding: const material.EdgeInsets.all(24),
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
                    children: [
                      const Text('Connection Name').small().semiBold(),
                      const Gap(8),
                      TextField(
                      controller: _nameController,
                      placeholder: const Text('My MySQL Server'),
                    ),
                    const Gap(16),
                    const Text('Connection URI (optional)').small().semiBold(),
                    const Gap(4),
                    const Text(
                      'If set, overrides Host / Port / Database below.',
                    ).muted().small(),
                    const Gap(4),
                    const Text(
                      'Query params: ssl-mode (disable, require), database, '
                      'sslrootcert, sslcert, sslkey.',
                    ).muted().small(),
                    const Gap(8),
                    TextField(
                      controller: _connectionStringController,
                      placeholder: const Text(
                        'mysql://user:pass@host:3306/dbname?ssl-mode=disable',
                      ),
                    ),
                    const Gap(16),
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
                                placeholder: const Text('3306'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    const Text('Database (optional)').small().semiBold(),
                    const Gap(8),
                    TextField(
                      controller: _databaseController,
                      placeholder: const Text('Leave empty to browse all'),
                    ),
                    const Gap(16),
                    const Text('Username').small().semiBold(),
                    const Gap(8),
                    TextField(
                      controller: _usernameController,
                      placeholder: const Text('root'),
                    ),
                    const Gap(16),
                    const Text('Password').small().semiBold(),
                    const Gap(8),
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
                    material.Row(
                      children: [
                        material.Checkbox(
                          value: _useSSL,
                          onChanged: (v) => setState(() => _useSSL = v ?? true),
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
                  ),
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
            material.FocusTraversalGroup(
              policy: material.WidgetOrderTraversalPolicy(),
              child: material.Container(
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
            ),
          ],
        ),
      ),
    );
  }
}
