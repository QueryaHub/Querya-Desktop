import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/shared/widgets/form_validity_notifier.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows PostgreSQL connection form dialog.
/// Returns ConnectionRow if saved, null if cancelled.
Future<ConnectionRow?> showPostgresConnectionForm(
  BuildContext context, {
  int? folderId,
  ConnectionRow? initial,
}) async {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _PostgresConnectionFormContent(
        folderId: folderId,
        initial: initial,
      ),
    ),
  );
}

class _PostgresConnectionFormContent extends material.StatefulWidget {
  const _PostgresConnectionFormContent({this.folderId, this.initial});

  final int? folderId;
  final ConnectionRow? initial;

  @override
  material.State<_PostgresConnectionFormContent> createState() =>
      _PostgresConnectionFormContentState();
}

class _PostgresConnectionFormContentState
    extends material.State<_PostgresConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _hostController = material.TextEditingController(text: 'localhost');
  final _portController = material.TextEditingController(text: '5432');
  final _databaseController = material.TextEditingController(text: 'postgres');
  final _usernameController = material.TextEditingController(text: 'postgres');
  final _passwordController = material.TextEditingController();
  final _connectionStringController = material.TextEditingController();
  final _sslRootCertController = material.TextEditingController();
  final _sslCertController = material.TextEditingController();
  final _sslKeyController = material.TextEditingController();

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
      _portController.text = (initial.port ?? 5432).toString();
      _usernameController.text = initial.username ?? '';
      _databaseController.text = initial.databaseName ?? '';
      _useSSL = initial.useSSL;
      _connectionStringController.text =
          redactUriPassword(initial.connectionString) ?? '';
      // Password left empty — mergeSecretsForConnectionUpdate keeps existing.
    }

    _formValidNotifier.seed();
  }

  bool _computeFormValid() {
    final uri = _connectionStringController.text.trim();
    if (uri.isNotEmpty) {
      return _looksLikePostgresUri(uri);
    }
    final host = _hostController.text.trim();
    final db = _databaseController.text.trim();
    return host.isNotEmpty && db.isNotEmpty;
  }

  bool _looksLikePostgresUri(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('postgres://') || t.startsWith('postgresql://');
  }

  void _populateSslFieldsFromUri() {
    final uriText = _connectionStringController.text.trim();
    if (uriText.isEmpty) return;
    final parsed = Uri.tryParse(uriText);
    if (parsed == null) return;
    _sslRootCertController.text = parsed.queryParameters['sslrootcert'] ?? '';
    _sslCertController.text = parsed.queryParameters['sslcert'] ?? '';
    _sslKeyController.text = parsed.queryParameters['sslkey'] ?? '';
  }

  void _setOrRemoveSslParam(
    Map<String, String> params,
    String key,
    material.TextEditingController controller,
  ) {
    final value = controller.text.trim();
    if (value.isEmpty) {
      params.remove(key);
    } else {
      params[key] = value;
    }
  }

  void _syncUriSslParams() {
    final uriText = _connectionStringController.text.trim();
    if (uriText.isEmpty) return;
    final parsed = Uri.tryParse(uriText);
    if (parsed == null) return;
    final params = Map<String, String>.from(parsed.queryParameters);
    _setOrRemoveSslParam(params, 'sslrootcert', _sslRootCertController);
    _setOrRemoveSslParam(params, 'sslcert', _sslCertController);
    _setOrRemoveSslParam(params, 'sslkey', _sslKeyController);
    final newUri = Uri(
      scheme: parsed.scheme,
      userInfo: parsed.userInfo.isEmpty ? null : parsed.userInfo,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: parsed.path.isEmpty ? null : parsed.path,
      queryParameters: params.isEmpty ? null : params,
      fragment: parsed.fragment.isEmpty ? null : parsed.fragment,
    );
    _connectionStringController.text = newUri.toString();
    _formValidNotifier.seed();
  }

  Future<void> _pickCertificateFile(
    material.TextEditingController controller,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'PEM files',
      extensions: ['pem', 'crt', 'key', 'cer'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    controller.text = file.path;
    _syncUriSslParams();
  }

  String _buildConnectionUri({
    required String host,
    required int port,
    String? username,
    String? password,
    String? database,
    String? sslRootCert,
    String? sslCert,
    String? sslKey,
  }) {
    final userInfoParts = <String>[
      if (username != null && username.isNotEmpty)
        Uri.encodeComponent(username),
      if (password != null && password.isNotEmpty)
        Uri.encodeComponent(password),
    ];
    final queryParams = <String, String>{
      if (sslRootCert != null && sslRootCert.isNotEmpty)
        'sslrootcert': sslRootCert,
      if (sslCert != null && sslCert.isNotEmpty) 'sslcert': sslCert,
      if (sslKey != null && sslKey.isNotEmpty) 'sslkey': sslKey,
    };
    return Uri(
      scheme: 'postgresql',
      userInfo: userInfoParts.join(':'),
      host: host,
      port: port,
      path: database == null || database.isEmpty ? '' : '/$database',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    ).toString();
  }

  String _effectiveConnectionUri() {
    final uri = _connectionStringController.text.trim();
    if (uri.isNotEmpty) return uri;
    final sslRootCert = _sslRootCertController.text.trim();
    final sslCert = _sslCertController.text.trim();
    final sslKey = _sslKeyController.text.trim();
    if (sslRootCert.isEmpty && sslCert.isEmpty && sslKey.isEmpty) return '';
    return _buildConnectionUri(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 5432,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      database: _databaseController.text.trim(),
      sslRootCert: sslRootCert,
      sslCert: sslCert,
      sslKey: sslKey,
    );
  }

  bool _hasSslCertificateFields() {
    return _sslRootCertController.text.trim().isNotEmpty ||
        _sslCertController.text.trim().isNotEmpty ||
        _sslKeyController.text.trim().isNotEmpty;
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
      final hasUri = uri.isNotEmpty;
      final conn = PostgresConnection(
        id: 0,
        name: _nameController.text.trim().isEmpty
            ? 'test'
            : _nameController.text.trim(),
        host: hasUri ? 'localhost' : _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 5432,
        database: _databaseController.text.trim().isEmpty
            ? null
            : _databaseController.text.trim(),
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        password:
            _passwordController.text.isEmpty ? null : _passwordController.text,
        useSSL: _useSSL || _hasSslCertificateFields(),
        connectionString: hasUri ? uri : null,
        sslRootCert: _sslRootCertController.text.trim().isEmpty
            ? null
            : _sslRootCertController.text.trim(),
        sslCert: _sslCertController.text.trim().isEmpty
            ? null
            : _sslCertController.text.trim(),
        sslKey: _sslKeyController.text.trim().isEmpty
            ? null
            : _sslKeyController.text.trim(),
      );
      final result = await conn.testConnection();
      if (mounted) {
        _showTestResult(
          result.ok ? 'success' : (result.error ?? 'failed'),
        );
      }
    } catch (e) {
      if (mounted) _showTestResult('error: $e');
    }
  }

  void _save() {
    if (!_formValidNotifier.value) return;
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 5432;
    final database = _databaseController.text.trim();

    _syncUriSslParams();
    final effectiveUri = _effectiveConnectionUri();
    final hasSslCerts = _hasSslCertificateFields();
    final effectiveUseSSL = _useSSL || hasSslCerts;

    String? uriHost;
    int? uriPort;
    if (effectiveUri.isNotEmpty) {
      final parsedUri = Uri.tryParse(effectiveUri);
      if (parsedUri != null && parsedUri.host.isNotEmpty) {
        uriHost = parsedUri.host;
        uriPort = parsedUri.hasPort ? parsedUri.port : null;
      }
    }

    final effectiveHost = uriHost ?? host;
    final effectivePort = uriPort ?? port;
    final displayName = name.isNotEmpty
        ? name
        : (effectiveUri.isNotEmpty
            ? 'PostgreSQL: $effectiveHost:$effectivePort'
            : 'PostgreSQL $host:$port/$database');
    final initial = widget.initial;
    final row = ConnectionRow(
      id: initial?.id,
      type: initial?.type ?? 'postgresql',
      name: displayName,
      host: uriHost ?? (effectiveUri.isEmpty ? host : null),
      port: uriPort ?? (effectiveUri.isEmpty ? port : null),
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      password:
          _passwordController.text.isEmpty ? null : _passwordController.text,
      databaseName:
          effectiveUri.isNotEmpty ? null : (database.isEmpty ? null : database),
      useSSL: effectiveUseSSL,
      connectionString: effectiveUri.isEmpty ? null : effectiveUri,
      extensionId: initial?.extensionId,
      driverOptions: initial?.driverOptions,
      folderId: initial?.folderId ?? widget.folderId,
      sortOrder: initial?.sortOrder ?? 0,
      createdAt: initial?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
    );
    material.Navigator.of(context).pop(row);
  }

  material.Widget _buildSslFileField({
    required String label,
    required material.TextEditingController controller,
  }) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        Text(label).xSmall().muted(),
        const Gap(4),
        material.Row(
          children: [
            material.Expanded(
              child: TextField(
                key: Key(label),
                controller: controller,
                placeholder: const Text('/path/to/file.pem'),
                onChanged: (_) => _syncUriSslParams(),
              ),
            ),
            const Gap(8),
            GhostButton(
              onPressed: () => _pickCertificateFile(controller),
              child: const Icon(material.Icons.folder_open_rounded),
            ),
          ],
        ),
      ],
    );
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
            // Header
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
                          'assets/images/postgresql_icon.png',
                          cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                          cacheHeight: (40 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                          fit: material.BoxFit.contain,
                          errorBuilder: (_, __, ___) => material.Icon(
                            material.Icons.storage_rounded,
                            size: 24,
                            color: theme.primary,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Text(
                        _isEditing
                            ? 'Edit PostgreSQL Connection'
                            : 'PostgreSQL Connection',
                      ).large().semiBold(),
                    ],
                  ),
                  const Gap(8),
                  const Text('Configure your PostgreSQL connection settings')
                      .muted()
                      .small(),
                ],
              ),
            ),
            const material.Divider(height: 1),
            // Form body
            material.Expanded(
              child: material.FocusTraversalGroup(
                policy: material.WidgetOrderTraversalPolicy(),
                child: material.SingleChildScrollView(
                  padding: const material.EdgeInsets.all(24),
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
                    children: [
                      // Connection Name
                      const Text('Connection Name').small().semiBold(),
                      const Gap(8),
                      TextField(
                        controller: _nameController,
                        placeholder: const Text('My PostgreSQL Server'),
                      ),
                      const Gap(16),
                      const Text('Connection URI (optional)').small().semiBold(),
                      const Gap(4),
                      const Text(
                        'If set, overrides Host / Port / Database below.',
                      ).muted().small(),
                      const Gap(4),
                      const Text(
                        'Supported query params include sslmode (disable, require, '
                        'verify-ca, verify-full), connect_timeout and query_timeout '
                        '(seconds). If sslmode is omitted, Use SSL/TLS below applies.',
                      ).muted().small(),
                      const Gap(8),
                      TextField(
                        controller: _connectionStringController,
                        placeholder: const Text(
                          'postgresql://user:pass@host:5432/dbname?sslmode=require',
                        ),
                      ),
                      const Gap(16),
                      // Host and Port Row
                      material.Row(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          material.Expanded(
                            flex: 3,
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
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
                          const Gap(16),
                          material.Expanded(
                            flex: 2,
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              children: [
                                const Text('Port').small().semiBold(),
                                const Gap(8),
                                TextField(
                                  controller: _portController,
                                  placeholder: const Text('5432'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Gap(16),
                      // Database
                      const Text('Database').small().semiBold(),
                      const Gap(8),
                      TextField(
                        controller: _databaseController,
                        placeholder: const Text('postgres'),
                      ),
                      const Gap(16),
                      // Username and Password Row
                      material.Row(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          material.Expanded(
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              children: [
                                const Text('Username').small().semiBold(),
                                const Gap(8),
                                TextField(
                                  controller: _usernameController,
                                  placeholder: const Text('postgres'),
                                ),
                              ],
                            ),
                          ),
                          const Gap(16),
                          material.Expanded(
                            child: material.Column(
                              crossAxisAlignment:
                                  material.CrossAxisAlignment.stretch,
                              children: [
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
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Gap(16),
                      // SSL/TLS Toggle
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
                        material.FocusTraversalGroup(
                          policy: material.WidgetOrderTraversalPolicy(),
                          child: material.Column(
                            crossAxisAlignment:
                                material.CrossAxisAlignment.stretch,
                            children: [
                              const Text('SSL Certificates (optional)')
                                  .small()
                                  .semiBold(),
                              const Gap(4),
                              const Text(
                                'Root CA, client certificate, and client key are '
                                'appended to the connection URI.',
                              ).muted().small(),
                              const Gap(8),
                              _buildSslFileField(
                                label: 'Root CA / SSL Root Certificate',
                                controller: _sslRootCertController,
                              ),
                              const Gap(8),
                              _buildSslFileField(
                                label: 'SSL Client Certificate',
                                controller: _sslCertController,
                              ),
                              const Gap(8),
                              _buildSslFileField(
                                label: 'SSL Client Key',
                                controller: _sslKeyController,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
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
            // Footer — Wrap avoids overflow on narrow viewports (e.g. in tests)
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
