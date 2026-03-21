import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows Redis connection form dialog. Returns ConnectionRow if saved, null if cancelled.
Future<ConnectionRow?> showRedisConnectionForm(
  BuildContext context, {
  int? folderId,
}) async {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: const material.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: _RedisConnectionFormContent(folderId: folderId),
    ),
  );
}

class _RedisConnectionFormContent extends material.StatefulWidget {
  const _RedisConnectionFormContent({this.folderId});

  final int? folderId;

  @override
  material.State<_RedisConnectionFormContent> createState() => _RedisConnectionFormContentState();
}

class _RedisConnectionFormContentState extends material.State<_RedisConnectionFormContent> {
  final _nameController = material.TextEditingController();
  final _hostController = material.TextEditingController(text: 'localhost');
  final _portController = material.TextEditingController(text: '6379');
  final _usernameController = material.TextEditingController();
  final _passwordController = material.TextEditingController();

  bool _showPassword = false;
  bool _isTesting = false;
  String? _testResult;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFieldChanged);
    _hostController.addListener(_onFieldChanged);
    _portController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  bool get _formValid {
    final host = _hostController.text.trim();
    return host.isNotEmpty && (_nameController.text.trim().isNotEmpty || host.isNotEmpty);
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
    if (!_formValid) return;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final conn = RedisConnection(
        id: 0,
        name: _nameController.text.trim().isEmpty ? 'test' : _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 6379,
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
      );
      final ok = await conn.testConnection();
      if (mounted) _showTestResult(ok ? 'success' : 'failed');
    } catch (e) {
      if (mounted) _showTestResult('error: $e');
    }
  }

  void _save() {
    if (!_formValid) return;
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 6379;
    final displayName = name.isNotEmpty ? name : 'Redis $host:$port';
    final row = ConnectionRow(
      type: 'redis',
      name: displayName,
      host: host,
      port: port,
      username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
      password: _passwordController.text.isEmpty ? null : _passwordController.text,
      folderId: widget.folderId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    material.Navigator.of(context).pop(row);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _nameController.removeListener(_onFieldChanged);
    _hostController.removeListener(_onFieldChanged);
    _portController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;

    return material.Container(
      constraints: const material.BoxConstraints(maxWidth: 600, maxHeight: 560),
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
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Row(
                    children: [
                      material.Icon(material.Icons.memory_rounded, size: 24, color: theme.primary),
                      const Gap(12),
                      const Text('Redis Connection').large().semiBold(),
                    ],
                  ),
                  const Gap(8),
                  const Text('Configure Redis connection.').muted().small(),
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
                    const Text('Connection Name').small().semiBold(),
                    const Gap(8),
                    TextField(
                      controller: _nameController,
                      placeholder: const Text('My Redis Server'),
                    ),
                    const Gap(16),
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
                                placeholder: const Text('6379'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    const Text('Username (optional, Redis 6+ ACL)').small().semiBold(),
                    const Gap(8),
                    TextField(
                      controller: _usernameController,
                      placeholder: const Text('default (leave empty for default user)'),
                    ),
                    const Gap(16),
                    const Text('Password (optional)').small().semiBold(),
                    const Gap(8),
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
                                _showPassword
                                    ? material.Icons.visibility_off
                                    : material.Icons.visibility,
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
                      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: material.Row(
                children: [
                  OutlineButton(
                    onPressed: _formValid && !_isTesting ? _testConnection : null,
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
                            color: _formValid ? theme.primary : theme.mutedForeground,
                          ),
                    child: Text(
                      'Test Connection',
                      style: material.TextStyle(
                        fontWeight: material.FontWeight.w500,
                        color: _formValid ? theme.primary : theme.mutedForeground,
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
                    onPressed: _formValid ? _save : null,
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
