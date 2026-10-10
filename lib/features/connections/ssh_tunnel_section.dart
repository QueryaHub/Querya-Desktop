import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';
import 'package:querya_desktop/features/connections/connection_edit_secrets.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable UI section for configuring SSH Bastion / Jump Host tunneling
/// in connection dialogs.
class SshTunnelSection extends material.StatefulWidget {
  const SshTunnelSection({
    super.key,
    required this.config,
    required this.secrets,
    required this.onChanged,
    this.targetHost,
    this.targetPort,
    this.connectionId,
  });

  final SshTunnelConfig config;
  final SshTunnelSecrets secrets;
  final material.ValueChanged<SshTunnelConfig> onChanged;
  final String? targetHost;
  final int? targetPort;

  /// The saved connection being edited: its stored SSH secrets stand in for
  /// the fields left blank when the tunnel is tested (#1302).
  final int? connectionId;

  @override
  material.State<SshTunnelSection> createState() => _SshTunnelSectionState();
}

class _SshTunnelSectionState extends material.State<SshTunnelSection> {
  late final material.TextEditingController _hostController;
  late final material.TextEditingController _portController;
  late final material.TextEditingController _usernameController;
  late final material.TextEditingController _passwordController;
  late final material.TextEditingController _keyPathController;
  late final material.TextEditingController _passphraseController;
  late final material.TextEditingController _fingerprintController;

  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
  bool _showAdvanced = false;
  bool _testing = false;
  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _hostController = material.TextEditingController(text: widget.config.host);
    _portController =
        material.TextEditingController(text: widget.config.port.toString());
    _usernameController =
        material.TextEditingController(text: widget.config.username);
    _passwordController =
        material.TextEditingController(text: widget.secrets.password ?? '');
    _keyPathController = material.TextEditingController(
        text: widget.config.privateKeyPath ?? '');
    _passphraseController =
        material.TextEditingController(text: widget.secrets.passphrase ?? '');
    _fingerprintController = material.TextEditingController(
        text: widget.config.knownHostFingerprint ?? '');

    _hostController.addListener(_notify);
    _portController.addListener(_notify);
    _usernameController.addListener(_notify);
    _passwordController.addListener(() {
      widget.secrets.password = _passwordController.text;
    });
    _keyPathController.addListener(_notify);
    _passphraseController.addListener(() {
      widget.secrets.passphrase = _passphraseController.text;
    });
    _fingerprintController.addListener(_notify);
  }

  @override
  void didUpdateWidget(SshTunnelSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      if (_hostController.text != widget.config.host) {
        _hostController.text = widget.config.host;
      }
      if (_portController.text != widget.config.port.toString()) {
        _portController.text = widget.config.port.toString();
      }
      if (_usernameController.text != widget.config.username) {
        _usernameController.text = widget.config.username;
      }
      if (_keyPathController.text != (widget.config.privateKeyPath ?? '')) {
        _keyPathController.text = widget.config.privateKeyPath ?? '';
      }
      if (_fingerprintController.text !=
          (widget.config.knownHostFingerprint ?? '')) {
        _fingerprintController.text = widget.config.knownHostFingerprint ?? '';
      }
    }
    if (widget.secrets.password != null &&
        widget.secrets.password!.isNotEmpty &&
        _passwordController.text.isEmpty) {
      _passwordController.text = widget.secrets.password!;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _keyPathController.dispose();
    _passphraseController.dispose();
    _fingerprintController.dispose();
    super.dispose();
  }

  void _notify() {
    final updated = widget.config.copyWith(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: _usernameController.text.trim(),
      privateKeyPath: _keyPathController.text.trim().isEmpty
          ? null
          : _keyPathController.text.trim(),
      knownHostFingerprint: _fingerprintController.text.trim().isEmpty
          ? null
          : _fingerprintController.text.trim(),
    );
    widget.onChanged(updated);
  }

  Future<void> _pickPrivateKeyFile() async {
    const typeGroup = XTypeGroup(
      label: 'SSH Keys',
      extensions: ['pem', 'key', 'id_rsa', 'id_ed25519', 'id_ecdsa'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file != null) {
      _keyPathController.text = file.path;
      _notify();
    }
  }

  Future<void> _testSsh() async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });

    final currentConfig = widget.config.copyWith(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: _usernameController.text.trim(),
      privateKeyPath: _keyPathController.text.trim().isEmpty
          ? null
          : _keyPathController.text.trim(),
      knownHostFingerprint: _fingerprintController.text.trim().isEmpty
          ? null
          : _fingerprintController.text.trim(),
    );

    final id = widget.connectionId;
    final secrets = id == null || id <= 0
        ? widget.secrets.copy()
        : await mergeSshSecretsForConnectionUpdate(
            connectionId: id,
            editedSecrets: widget.secrets,
          );
    final result = await SshTunnelManager.instance.testSshConnection(
      config: currentConfig,
      secrets: secrets,
      testRemoteHost: widget.targetHost,
      testRemotePort: widget.targetPort,
    );

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSuccess = result.ok;
      if (result.ok) {
        _testMessage = result.serverFingerprint != null
            ? 'Connected! Host fingerprint: ${result.serverFingerprint}'
            : 'SSH Bastion connection verified successfully!';
      } else {
        _testMessage = result.error ?? 'SSH Connection failed';
      }
    });
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return material.Container(
      margin: const material.EdgeInsets.only(top: 16),
      padding: const material.EdgeInsets.all(14),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.15),
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color: widget.config.enabled
              ? cs.primary.withValues(alpha: 0.5)
              : cs.border.withValues(alpha: 0.4),
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Row(
            children: [
              material.Checkbox(
                value: widget.config.enabled,
                onChanged: (v) {
                  widget.onChanged(widget.config.copyWith(enabled: v ?? false));
                },
              ),
              const Gap(4),
              material.Icon(
                material.Icons.security_rounded,
                size: 16,
                color: widget.config.enabled ? cs.primary : cs.mutedForeground,
              ),
              const Gap(6),
              material.Expanded(
                child: const Text(
                  'Connect via SSH Tunnel (Bastion / Jump Host)',
                ).semiBold().small(),
              ),
            ],
          ),
          if (widget.config.enabled) ...[
            const Gap(14),
            material.Row(
              children: [
                material.Expanded(
                  flex: 3,
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      const Text('Bastion Host').small().muted(),
                      const Gap(4),
                      TextField(
                        controller: _hostController,
                        placeholder: const Text('bastion.corp.example.com'),
                      ),
                    ],
                  ),
                ),
                const Gap(8),
                material.Expanded(
                  flex: 1,
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      const Text('SSH Port').small().muted(),
                      const Gap(4),
                      TextField(
                        controller: _portController,
                        placeholder: const Text('22'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(12),
            material.Row(
              children: [
                material.Expanded(
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      const Text('SSH Username').small().muted(),
                      const Gap(4),
                      TextField(
                        controller: _usernameController,
                        placeholder: const Text('ubuntu / root / ec2-user'),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                material.Expanded(
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    children: [
                      const Text('Authentication Method').small().muted(),
                      const Gap(4),
                      material.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _AuthTypeChip(
                            label: 'Password',
                            selected:
                                widget.config.authType == SshAuthType.password,
                            onTap: () {
                              widget.onChanged(widget.config.copyWith(
                                authType: SshAuthType.password,
                              ));
                            },
                          ),
                          _AuthTypeChip(
                            label: 'Private Key',
                            selected: widget.config.authType ==
                                SshAuthType.privateKey,
                            onTap: () {
                              widget.onChanged(widget.config.copyWith(
                                authType: SshAuthType.privateKey,
                              ));
                            },
                          ),
                          _AuthTypeChip(
                            label: 'Agent',
                            selected:
                                widget.config.authType == SshAuthType.sshAgent,
                            onTap: () {
                              widget.onChanged(widget.config.copyWith(
                                authType: SshAuthType.sshAgent,
                              ));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(12),
            if (widget.config.authType == SshAuthType.password) ...[
              material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('SSH Password').small().muted(),
                  const Gap(4),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    placeholder: const Text('••••••••'),
                    features: [
                      InputFeature.trailing(
                        IconButton.ghost(
                          size: ButtonSize.small,
                          icon: material.Icon(
                            _obscurePassword
                                ? material.Icons.visibility_off_outlined
                                : material.Icons.visibility_outlined,
                            size: 16,
                          ),
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else if (widget.config.authType == SshAuthType.privateKey) ...[
              material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.end,
                children: [
                  material.Expanded(
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        const Text('Private Key Path (PEM / OpenSSH / RSA)')
                            .small()
                            .muted(),
                        const Gap(4),
                        TextField(
                          controller: _keyPathController,
                          placeholder: const Text('~/.ssh/id_rsa or click Browse'),
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  OutlineButton(
                    onPressed: _pickPrivateKeyFile,
                    child: const Text('Browse…'),
                  ),
                ],
              ),
              const Gap(10),
              material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Key Passphrase (optional)').small().muted(),
                  const Gap(4),
                  TextField(
                    controller: _passphraseController,
                    obscureText: _obscurePassphrase,
                    placeholder: const Text('Passphrase if key is encrypted'),
                    features: [
                      InputFeature.trailing(
                        IconButton.ghost(
                          size: ButtonSize.small,
                          icon: material.Icon(
                            _obscurePassphrase
                                ? material.Icons.visibility_off_outlined
                                : material.Icons.visibility_outlined,
                            size: 16,
                          ),
                          onPressed: () {
                            setState(
                              () => _obscurePassphrase = !_obscurePassphrase,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              material.Container(
                padding: const material.EdgeInsets.all(10),
                decoration: material.BoxDecoration(
                  color: cs.muted.withValues(alpha: 0.2),
                  borderRadius: material.BorderRadius.circular(6),
                ),
                child: const Text(
                  'Authenticates using the local SSH Agent via \$SSH_AUTH_SOCK (Linux/macOS) or Named Pipe (Windows).',
                ).muted().xSmall(),
              ),
            ],
            const Gap(12),
            // Actions: Test SSH Connection and Advanced Options toggle
            material.Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: material.WrapCrossAlignment.center,
              children: [
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _testing ? null : _testSsh,
                  leading: _testing
                      ? const QueryaSpinner(size: QueryaSpinnerSize.sm)
                      : const material.Icon(
                          material.Icons.network_check_rounded,
                          size: 15,
                        ),
                  child: const Text('Test SSH Connection'),
                ),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: () =>
                      setState(() => _showAdvanced = !_showAdvanced),
                  child: Text(_showAdvanced
                      ? 'Hide Advanced ▲'
                      : 'Advanced (Host Key & Keep-Alive) ▼'),
                ),
              ],
            ),
            if (_testMessage != null) ...[
              const Gap(8),
              material.SelectableText(
                _testMessage!,
                style: material.TextStyle(
                  fontSize: 12,
                  color: _testSuccess
                      ? material.Colors.green
                      : cs.destructive,
                ),
              ),
            ],
            if (_showAdvanced) ...[
              const Gap(12),
              material.Container(
                padding: const material.EdgeInsets.all(10),
                decoration: material.BoxDecoration(
                  color: cs.muted.withValues(alpha: 0.1),
                  borderRadius: material.BorderRadius.circular(6),
                  border: material.Border.all(
                    color: cs.border.withValues(alpha: 0.3),
                  ),
                ),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    const Text('Known host fingerprint (optional)')
                        .small()
                        .muted(),
                    const Gap(4),
                    TextField(
                      controller: _fingerprintController,
                      placeholder: const Text(
                        'SHA256:... (leave blank to trust on first connect)',
                      ),
                    ),
                    const Gap(6),
                    const Text(
                      'Protects against Man-in-the-Middle (MitM) attacks by '
                      'rejecting mismatched host keys. Paste what '
                      '"ssh-keygen -lf" prints for the server\'s key, or the '
                      'fingerprint shown by Test SSH Connection.',
                    ).muted().xSmall(),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AuthTypeChip extends material.StatelessWidget {
  const _AuthTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final material.VoidCallback onTap;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.InkWell(
      onTap: onTap,
      borderRadius: material.BorderRadius.circular(6),
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: material.BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.18)
              : cs.muted.withValues(alpha: 0.25),
          borderRadius: material.BorderRadius.circular(6),
          border: material.Border.all(
            color: selected ? cs.primary : cs.border.withValues(alpha: 0.4),
          ),
        ),
        child: Text(label)
            .xSmall()
            .semiBold(),
      ),
    );
  }
}
