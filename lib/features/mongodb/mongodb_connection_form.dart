import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
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
}) async {
  return showDialog<ConnectionRow>(
    context: context,
    barrierColor: material.Colors.black54,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: const material.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: _MongoConnectionFormContent(folderId: folderId),
    ),
  );
}

class _MongoConnectionFormContent extends material.StatefulWidget {
  const _MongoConnectionFormContent({this.folderId});

  final int? folderId;

  @override
  material.State<_MongoConnectionFormContent> createState() => _MongoConnectionFormContentState();
}

class _MongoConnectionFormContentState extends material.State<_MongoConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _hostController = material.TextEditingController(text: 'localhost');
  final _portController = material.TextEditingController(text: '27017');
  final _usernameController = material.TextEditingController();
  final _passwordController = material.TextEditingController();
  final _databaseController = material.TextEditingController();
  final _authSourceController = material.TextEditingController();
  final _connectionStringController = material.TextEditingController();

  bool _useConnectionString = false;
  bool _useSSL = false;
  bool _showPassword = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so Save button reacts to validity
    _nameController.addListener(_onFieldChanged);
    _hostController.addListener(_onFieldChanged);
    _portController.addListener(_onFieldChanged);
    _connectionStringController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _hostController.removeListener(_onFieldChanged);
    _portController.removeListener(_onFieldChanged);
    _connectionStringController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    _authSourceController.dispose();
    _connectionStringController.dispose();
    super.dispose();
  }

  MongoConnectionData get _formData => MongoConnectionData(
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 27017,
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        database: _databaseController.text.trim().isEmpty ? null : _databaseController.text.trim(),
        authSource: _authSourceController.text.trim().isEmpty ? null : _authSourceController.text.trim(),
        useSSL: _useSSL,
        connectionString: _connectionStringController.text.trim().isEmpty
            ? null
            : _connectionStringController.text.trim(),
      );

  String? _testResult;

  Future<void> _testConnection() async {
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

      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = success ? 'success' : 'failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = 'error: $e';
        });
      }
    }
  }

  void _save() {
    final data = _formData;
    if (!data.isValid) return;

    final displayName = data.name.isNotEmpty
        ? data.name
        : 'MongoDB ${data.host}:${data.port}';

    final row = ConnectionRow(
      type: 'mongodb',
      name: displayName,
      host: data.host,
      port: data.port,
      username: data.username,
      password: data.password,
      databaseName: data.database,
      authSource: data.authSource,
      useSSL: data.useSSL,
      connectionString: data.connectionString,
      folderId: widget.folderId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    material.Navigator.of(context).pop(row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;

    return material.Container(
      constraints: const material.BoxConstraints(maxWidth: 600, maxHeight: 700),
      decoration: material.BoxDecoration(
        color: theme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: theme.muted),
      ),
      child: material.ClipRRect(
        borderRadius: material.BorderRadius.circular(radius),
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
                      const Text('MongoDB Connection').large().semiBold(),
                    ],
                  ),
                  const Gap(8),
                  const Text('Configure your MongoDB connection settings').muted().small(),
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
                          onChanged: (v) => setState(() => _useConnectionString = v ?? false),
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
                        placeholder: const Text('mongodb://username:password@host:port/database'),
                        maxLines: 2,
                      ),
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
                              crossAxisAlignment: material.CrossAxisAlignment.stretch,
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
                              crossAxisAlignment: material.CrossAxisAlignment.stretch,
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
                      const Text('Authentication (Optional)').small().semiBold(),
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
                            placeholder: const Text('Password'),
                            obscureText: !_showPassword,
                          ),
                          material.Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: material.Center(
                              child: material.IconButton(
                                icon: material.Icon(
                                  _showPassword ? material.Icons.visibility_off : material.Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
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
                              crossAxisAlignment: material.CrossAxisAlignment.stretch,
                              mainAxisSize: material.MainAxisSize.min,
                              children: [
                                const Text('Default Database (Optional)').small().semiBold(),
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
                              crossAxisAlignment: material.CrossAxisAlignment.stretch,
                              mainAxisSize: material.MainAxisSize.min,
                              children: [
                                const Text('Auth Source (Optional)').small().semiBold(),
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
                            onChanged: (v) => setState(() => _useSSL = v ?? false),
                          ),
                          const Gap(8),
                          const Text('Use SSL/TLS').small(),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const material.Divider(height: 1),
            if (_testResult != null)
              material.Container(
                padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                color: _testResult == 'success'
                    ? material.Colors.green.withValues(alpha: 0.1)
                    : material.Colors.red.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    material.Icon(
                      _testResult == 'success'
                          ? material.Icons.check_circle_rounded
                          : material.Icons.error_rounded,
                      size: 16,
                      color: _testResult == 'success'
                          ? material.Colors.green
                          : material.Colors.red,
                    ),
                    const Gap(8),
                    material.Expanded(
                      child: Text(
                        _testResult == 'success'
                            ? 'Connection successful!'
                            : _testResult!.startsWith('error:')
                                ? _testResult!.substring(7)
                                : 'Connection failed',
                      ).small(),
                    ),
                  ],
                ),
              ),
            material.Container(
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  GhostButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Gap(12),
                  OutlineButton(
                    onPressed: _isTesting ? null : _testConnection,
                    leading: _isTesting
                        ? const material.SizedBox(
                            width: 16,
                            height: 16,
                            child: material.CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const material.Icon(material.Icons.check_circle_outline, size: 18),
                    child: const Text('Test Connection'),
                  ),
                  const Gap(12),
                  PrimaryButton(
                    onPressed: _formData.isValid ? _save : null,
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
