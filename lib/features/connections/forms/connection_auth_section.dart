import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/connections/remove_saved_password_option.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable Username & Password input section for database connection forms (#1364).
class ConnectionAuthSection extends material.StatefulWidget {
  const ConnectionAuthSection({
    super.key,
    required this.usernameController,
    required this.passwordController,
    this.usernamePlaceholder = 'postgres',
    this.usernameLabel = 'Username',
    this.passwordLabel = 'Password',
    this.isEditing = false,
    this.removeSavedPassword = false,
    this.onRemoveSavedPasswordChanged,
    this.useRowLayout = true,
  });

  final material.TextEditingController usernameController;
  final material.TextEditingController passwordController;
  final String usernamePlaceholder;
  final String usernameLabel;
  final String passwordLabel;
  final bool isEditing;
  final bool removeSavedPassword;
  final material.ValueChanged<bool>? onRemoveSavedPasswordChanged;
  final bool useRowLayout;

  @override
  material.State<ConnectionAuthSection> createState() =>
      _ConnectionAuthSectionState();
}

class _ConnectionAuthSectionState extends material.State<ConnectionAuthSection> {
  bool _showPassword = false;

  material.Widget _buildUsernameField() {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        Text(widget.usernameLabel).small().semiBold(),
        const Gap(8),
        TextField(
          controller: widget.usernameController,
          placeholder: Text(widget.usernamePlaceholder),
        ),
      ],
    );
  }

  material.Widget _buildPasswordField() {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        Text(widget.passwordLabel).small().semiBold(),
        if (widget.isEditing && widget.onRemoveSavedPasswordChanged != null)
          RemoveSavedPasswordOption(
            value: widget.removeSavedPassword,
            onChanged: widget.onRemoveSavedPasswordChanged!,
          ),
        const Gap(8),
        material.Stack(
          children: [
            TextField(
              controller: widget.passwordController,
              enabled: !widget.removeSavedPassword,
              placeholder: Text(
                widget.isEditing ? 'Leave blank to keep existing' : 'Password',
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
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  padding: material.EdgeInsets.zero,
                  constraints: const material.BoxConstraints(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (widget.useRowLayout) {
      return material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Expanded(child: _buildUsernameField()),
          const Gap(16),
          material.Expanded(child: _buildPasswordField()),
        ],
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        _buildUsernameField(),
        const Gap(16),
        _buildPasswordField(),
      ],
    );
  }
}
